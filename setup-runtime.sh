#!/bin/bash

# Universal runtime setup with Procfile support

REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"
RUNTIME_FILE="$APP_DIR/runtime.txt"
PROCFILE="$APP_DIR/Procfile"

# Load deployment config
[ -f "$APP_DIR/.deployment" ] && source "$APP_DIR/.deployment" || {
    echo "BUILD_TYPE=auto" > "$APP_DIR/.deployment"
    echo "DEPLOYMENT_ROOT=$APP_DIR" >> "$APP_DIR/.deployment"
}

# Install from runtime.txt if exists
install_runtimes() {
    if [ -f "$RUNTIME_FILE" ]; then
        echo "🔍 Installing from runtime.txt..."
        while read -r line; do
            case $line in
                nodejs-*)
                    version=${line#nodejs-}
                    echo "⚡ Installing Node.js $version..."
                    curl -fsSL "https://deb.nodesource.com/setup_$version.x" | sudo -E bash -
                    sudo apt-get install -y nodejs
                    ;;
                python-*)
                    version=${line#python-}
                    echo "🐍 Installing Python $version..."
                    sudo apt-get install -y "python$version" "python$version-venv"
                    ;;
                java-*)
                    version=${line#java-}
                    echo "☕ Installing Java $version..."
                    sudo apt-get install -y "openjdk-$version-jdk"
                    ;;
                ruby-*)
                    version=${line#ruby-}
                    echo "💎 Installing Ruby $version..."
                    sudo apt-get install -y "ruby$version"
                    ;;
                *)
                    echo "⚠️ Unknown runtime: $line"
                    ;;
            esac
        done < "$RUNTIME_FILE"
    fi
}

# Process Procfile
process_procfile() {
    if [ -f "$PROCFILE" ]; then
        echo "🔍 Found Procfile - processing..."

        # Extract web process command
        WEB_CMD=$(grep '^web:' "$PROCFILE" | sed 's/web: //')
        
        if [ -n "$WEB_CMD" ]; then
            echo "🚀 Setting up web process: $WEB_CMD"
            SERVICE_FILE="/etc/systemd/system/${REPO_NAME}.service"

            cat > "$SERVICE_FILE" << EOF
[Unit]
Description=$REPO_NAME web process
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=/bin/bash -c '$WEB_CMD'
Restart=always
Environment=NODE_ENV=production
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin

[Install]
WantedBy=multi-user.target
EOF

            systemctl daemon-reload
            systemctl enable "${REPO_NAME}.service"
            systemctl start "${REPO_NAME}.service"

            echo "🔄 Created systemd service: ${REPO_NAME}.service"
        else
            echo "⚠️ No valid web process found in Procfile"
        fi

        # Extract worker process
        WORKER_CMD=$(grep '^worker:' "$PROCFILE" | sed 's/worker: //')
        if [ -n "$WORKER_CMD" ]; then
            echo "👷 Running worker process in background: $WORKER_CMD"
            nohup bash -c "cd $APP_DIR && $WORKER_CMD" > "$APP_DIR/worker.log" 2>&1 &
        fi

    else
        echo "ℹ️ No Procfile found - skipping process management"
    fi
}

# Main
cd "$APP_DIR" || exit 1

install_runtimes
process_procfile

# Final permissions
sudo chown -R $USER:www-data "$APP_DIR"
sudo chmod -R 775 "$APP_DIR"

echo "✅ Runtime setup complete"

