#!/bin/bash
REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"

# ----------------------------
# RUNTIME INSTALLATION
# ----------------------------
install_runtime() {
    # Clean existing Node.js if needed
    sudo apt-get purge -y nodejs npm 2>/dev/null
    
    if [ -f "$APP_DIR/runtime.txt" ]; then
        case $(cat "$APP_DIR/runtime.txt") in
            nodejs-*)
                version=$(cat "$APP_DIR/runtime.txt" | cut -d'-' -f2)
                curl -fsSL "https://deb.nodesource.com/setup_${version}.x" | sudo -E bash -
                sudo apt-get install -y nodejs
                ;;
            python-*)
                sudo apt-get install -y python3 python3-pip python3-venv
                ;;
            ruby-*)
                sudo apt-get install -y ruby bundler
                ;;
            java-*)
                sudo apt-get install -y openjdk-17-jdk maven
                ;;
        esac
    fi
}

# ----------------------------
# PROJECT DETECTION
# ----------------------------
find_app_dir() {
    # Check common directories (priority order)
    for dir in "$APP_DIR" "$APP_DIR/01basicvite" "$APP_DIR/app" "$APP_DIR/src"; do
        if [ -f "$dir/package.json" ] || [ -f "$dir/requirements.txt" ]; then
            echo "$dir"
            return
        fi
    done
    echo "$APP_DIR" # Fallback to root
}

APP_SUBFOLDER=$(find_app_dir)
echo "📂 Using project directory: $APP_SUBFOLDER"

# ----------------------------
# DEPENDENCY INSTALLATION
# ----------------------------
install_deps() {
    cd "$APP_SUBFOLDER"
    
    if [ -f "package.json" ]; then
        npm install
        [ -f "package-lock.json" ] && rm package-lock.json # Prevent conflicts
        if grep -q '"build"' package.json; then
            npm run build
        fi
    elif [ -f "requirements.txt" ]; then
        pip3 install -r requirements.txt
    elif [ -f "Gemfile" ]; then
        bundle install
    elif [ -f "pom.xml" ]; then
        mvn clean package
    fi
}

# ----------------------------
# SERVICE CREATION
# ----------------------------
create_service() {
    local port=${2:-3000} # Default port
    
    sudo bash -c "cat > /etc/systemd/system/${REPO_NAME}.service" <<EOF
[Unit]
Description=$REPO_NAME Service
After=network.target

[Service]
User=root
WorkingDirectory=$APP_SUBFOLDER
ExecStart=$1
Restart=always
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=PORT=$port

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${REPO_NAME}"
    sudo systemctl start "${REPO_NAME}"
}

# ----------------------------
# MAIN DEPLOYMENT LOGIC
# ----------------------------
install_runtime
install_deps

# Auto-detect start command
if [ -f "$APP_SUBFOLDER/package.json" ]; then
    create_service "npm run start" 5173
elif [ -f "$APP_SUBFOLDER/requirements.txt" ]; then
    create_service "gunicorn --bind 0.0.0.0:8000 app:app" 8000
else
    echo "⚠️ No auto-start configuration found"
fi

echo "✅ Deployment complete for $REPO_NAME"
echo "🔍 Check status: sudo systemctl status $REPO_NAME"
