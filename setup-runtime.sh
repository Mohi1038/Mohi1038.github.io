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
    cd "$APP_SUBFOLDER"
    
    # Check for dependency files in project root
    if [ -f "package.json" ]; then
        echo "📦 Installing Node.js dependencies"
        npm install
        [ -f "package-lock.json" ] && rm package-lock.json
        if grep -q '"build"' package.json; then
            echo "🏗️ Running build script"
            npm run build
        fi
    elif [ -f "requirements.txt" ]; then
        echo "🐍 Installing Python dependencies"
        pip3 install -r requirements.txt
    elif [ -f "Gemfile" ]; then
        echo "💎 Installing Ruby dependencies"
        bundle install
    elif [ -f "pom.xml" ]; then
        echo "☕ Building Java project"
        mvn clean package
    elif [ -f "go.mod" ]; then
        echo "🦫 Building Go project"
        go build
    elif [ -f "composer.json" ]; then
        echo "🐘 Installing PHP dependencies"
        composer install
    else
        echo "ℹ️ No recognized build files found - skipping dependency installation"
    fi
}

# ----------------------------
# SERVICE CREATION
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
            
            sudo bash -c "cat > /etc/systemd/system/${REPO_NAME}.service" <<EOF
[Unit]
Description=$REPO_NAME Service
After=network.target

[Service]
User=root
WorkingDirectory=$(dirname "$procfile")
ExecStart=/bin/bash -c "$command"
Restart=always
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

            sudo systemctl daemon-reload
            sudo systemctl enable "${REPO_NAME}"
            if ! sudo systemctl start "${REPO_NAME}"; then
                echo "❌ Failed to start service"
                echo "📜 Showing journal logs:"
                sudo journalctl -u "${REPO_NAME}" -n 20 --no-pager
                exit 1
            fi
            echo "✅ Service created and started"
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

echo "🎉 Universal deployment completed successfully!"
echo "🔍 Check service status: sudo systemctl status $REPO_NAME"
echo "📜 View logs: journalctl -u $REPO_NAME -f"
