#!/bin/bash
REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"

# ----------------------------
# UNIVERSAL FILE FINDER
# ----------------------------
find_project_root() {
    local current_dir="$1"
    
    # Look for typical root markers in current directory
    for marker in Procfile runtime.txt package.json requirements.txt Gemfile pom.xml; do
        if [ -f "$current_dir/$marker" ]; then
            echo "$current_dir"
            return
        fi
    done
    
    # Check immediate subdirectories if nothing found in root
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
    
    # Fallback to provided directory if nothing found
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
# SERVICE CREATION (IMPROVED RELIABILITY)
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

[Install]
WantedBy=multi-user.target
EOF

            # Reload and enable
            sudo systemctl daemon-reload
            sudo systemctl enable "${REPO_NAME}"
            
            # Start with health check
            echo "⏳ Starting service..."
            if ! sudo systemctl start "${REPO_NAME}"; then
                echo "❌ Initial start failed, retrying once..."
                sleep 2
                sudo systemctl restart "${REPO_NAME}" || {
                    echo "❌ Critical: Service failed to start"
                    journalctl -u "${REPO_NAME}" -n 15 --no-pager
                    exit 1
                }
            fi

            # Verify status
            sleep 1 # Brief pause for process spawn
            if ! sudo systemctl is-active --quiet "${REPO_NAME}"; then
                echo "⚠️ Service registered but not active, checking logs..."
                journalctl -u "${REPO_NAME}" -n 10 --no-pager
                exit 1
            fi

            echo "✅ Service created and running"
            return
        fi
    done < "$procfile"

    echo "⚠️ No web process found in Procfile"
    exit 1
}

# ----------------------------
# MAIN DEPLOYMENT LOGIC
# ----------------------------

# 1. Find the actual project root
APP_SUBFOLDER=$(find_project_root "$APP_DIR")
echo "📂 Detected project root: $APP_SUBFOLDER"

# 2. Install required runtime
install_runtime

# 3. Install project dependencies
install_dependencies

# 4. Create and start service
create_service

echo "🎉 Deployment completed successfully!"
echo "🔍 Check service: sudo systemctl status $REPO_NAME"
echo "📜 View logs: journalctl -u $REPO_NAME -f"
