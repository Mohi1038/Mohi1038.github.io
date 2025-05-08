#!/bin/bash
REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"

# ----------------------------
# UNIVERSAL FILE FINDER
# ----------------------------
find_project_root() {
    local current_dir="$1"
    
    for marker in Procfile runtime.txt package.json requirements.txt Gemfile pom.xml; do
        if [ -f "$current_dir/$marker" ]; then
            echo "$current_dir"
            return
        fi
    done
    
    for subdir in "$current_dir"/*; do
        if [ -d "$subdir" ]; then
            for marker in Procfile runtime.txt package.json requirements.txt Gemfile pom.xml; do
                if [ -f "$subdir/$marker" ]; then
                    echo "$subdir"
                    return
                fi
            done
        fi
    done
    
    echo "$current_dir"
}

# ----------------------------
# RUNTIME INSTALLATION
# ----------------------------
install_runtime() {
    local runtime_file=$(find "$APP_SUBFOLDER" -maxdepth 1 -name "runtime.txt" | head -1)
    [ -z "$runtime_file" ] && runtime_file=$(find "$APP_DIR" -maxdepth 1 -name "runtime.txt" | head -1)
    
    if [ -n "$runtime_file" ]; then
        echo "🔍 Found runtime configuration at $runtime_file"
        case $(cat "$runtime_file") in
            nodejs-*)
                version=$(cat "$runtime_file" | cut -d'-' -f2)
                echo "⚙️ Installing Node.js $version"
                curl -fsSL "https://deb.nodesource.com/setup_${version}.x" | sudo -E bash -
                sudo apt-get install -y nodejs
                ;;
            python-*)
                echo "⚙️ Installing Python"
                sudo apt-get install -y python3 python3-pip python3-venv
                ;;
            ruby-*)
                echo "⚙️ Installing Ruby"
                sudo apt-get install -y ruby bundler
                ;;
            java-*)
                echo "⚙️ Installing Java"
                sudo apt-get install -y openjdk-17-jdk maven
                ;;
            go-*)
                echo "⚙️ Installing Go"
                sudo apt-get install -y golang
                ;;
            php-*)
                echo "⚙️ Installing PHP"
                sudo apt-get install -y php
                ;;
            *)
                echo "⚠️ Unknown runtime specified in runtime.txt"
                ;;
        esac
    else
        echo "ℹ️ No runtime.txt found - skipping runtime installation"
    fi
}

# ----------------------------
# DEPENDENCY INSTALLATION
# ----------------------------
install_dependencies() {
    local found=0
    for dir in "$APP_SUBFOLDER" "$APP_SUBFOLDER"/*; do
        if [ -d "$dir" ]; then
            cd "$dir"
            if [ -f "package.json" ]; then
                echo "📦 Installing Node.js dependencies in $dir"
                npm install
                [ -f "package-lock.json" ] && rm package-lock.json
                if grep -q '"build"' package.json; then
                    echo "🏗️ Running build script"
                    npm run build
                fi
                found=1
                break
            elif [ -f "requirements.txt" ]; then
                echo "🐍 Installing Python dependencies in $dir"
                pip3 install -r requirements.txt
                found=1
                break
            elif [ -f "Gemfile" ]; then
                echo "💎 Installing Ruby dependencies in $dir"
                bundle install
                found=1
                break
            elif [ -f "pom.xml" ]; then
                echo "☕ Building Java project in $dir"
                mvn clean package
                found=1
                break
            elif [ -f "go.mod" ]; then
                echo "🦫 Building Go project in $dir"
                go build
                found=1
                break
            elif [ -f "composer.json" ]; then
                echo "🐘 Installing PHP dependencies in $dir"
                composer install
                found=1
                break
            fi
        fi
    done
    
    if [ "$found" -eq 0 ]; then
        echo "ℹ️ No recognized build files found - skipping dependency installation"
    fi
}

# ----------------------------
# SERVICE CREATION (WITH CRITICAL FIXES)
# ----------------------------
create_service() {
    local procfile=$(find "$APP_SUBFOLDER" -maxdepth 1 -name "Procfile" | head -1)
    [ -z "$procfile" ] && procfile=$(find "$APP_DIR" -maxdepth 1 -name "Procfile" | head -1)

    if [ -z "$procfile" ]; then
        echo "⚠️ No Procfile found - cannot create service"
        exit 1
    fi

    echo "🔍 Found Procfile at $procfile"

    while IFS=':' read -r process_type command; do
        process_type=$(echo "$process_type" | xargs)
        command=$(echo "$command" | xargs)
        
        if [[ "$process_type" == "web" ]]; then
            echo "🚀 Found web process command: $command"
            
            # Get absolute working directory
            local working_dir=$(dirname "$(realpath "$procfile")")
            
            # Auto-detect port from command if available
            local detected_port=$(echo "$command" | grep -oE '\-\-port[ =]([0-9]+)' | awk '{print $2}')
            [ -z "$detected_port" ] && detected_port=$(echo "$command" | grep -oE '\-p ([0-9]+)' | awk '{print $2}')

            sudo bash -c "cat > /etc/systemd/system/${REPO_NAME}.service" <<EOF
[Unit]
Description=$REPO_NAME Service
After=network.target

[Service]
User=root
WorkingDirectory=$working_dir
ExecStart=/bin/bash -c "$command"
Restart=always
RestartSec=5s
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${detected_port:+Environment=PORT=$detected_port}

[Install]
WantedBy=multi-user.target
EOF

            # Reload and enable
            sudo systemctl daemon-reload
            sudo systemctl enable "${REPO_NAME}"

            # Start with retry logic
            echo "⏳ Starting service (with retries)..."
            for attempt in {1..3}; do
                if sudo systemctl start "${REPO_NAME}"; then
                    sleep 3 # Critical wait period
                    if sudo systemctl is-active --quiet "${REPO_NAME}"; then
                        # Verify port if detected
                        if [ -n "$detected_port" ] && ! nc -z localhost "$detected_port"; then
                            echo "⚠️ Service running but port $detected_port not listening (attempt $attempt)"
                            [ $attempt -lt 3 ] && sleep 2 && continue
                        fi
                        echo "✅ Service successfully started"
                        return
                    fi
                fi
                echo "⚠️ Attempt $attempt failed, retrying..."
                sleep 2
            done

            echo "❌ Failed to start service after 3 attempts"
            echo "📜 Last logs:"
            journalctl -u "${REPO_NAME}" -n 15 --no-pager
            exit 1
        fi
    done < "$procfile"

    echo "⚠️ No web process found in Procfile"
    exit 1
}

# ----------------------------
# MAIN DEPLOYMENT LOGIC
# ----------------------------
APP_SUBFOLDER=$(find_project_root "$APP_DIR")
echo "📂 Detected project root: $APP_SUBFOLDER"

install_runtime
install_dependencies
create_service

echo "🎉 Deployment completed successfully!"
echo "🔍 Check service: sudo systemctl status $REPO_NAME"
echo "📜 View logs: journalctl -u $REPO_NAME -f"
