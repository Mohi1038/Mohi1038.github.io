#!/bin/bash

REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"
RUNTIME_FILE="$APP_DIR/runtime.txt"
PROCFILE="$APP_DIR/Procfile"

# ----------------------------
# RUNTIME INSTALLATION
# ----------------------------
install_runtime() {
    if [ -f "$RUNTIME_FILE" ]; then
        echo "🔍 Found runtime.txt at $RUNTIME_FILE"
        runtime=$(cat "$RUNTIME_FILE")
        case "$runtime" in
            nodejs-*)
                version=$(echo "$runtime" | cut -d'-' -f2)
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
                echo "⚠️ Unknown runtime specified in runtime.txt: $runtime"
                ;;
        esac
    else
        echo "ℹ️ No runtime.txt found — skipping runtime installation"
    fi
}

# ----------------------------
# SERVICE CREATION
# ----------------------------
create_service() {
    # Find Procfile (search up to 2 levels deep)
    local procfile=$(find "$APP_DIR" -maxdepth 2 -name "Procfile" | head -1)
    if [ -z "$procfile" ]; then
        echo "❌ No Procfile found in $APP_DIR or subdirectories"
        exit 1
    fi
    echo "🔍 Found Procfile at $procfile"

    # Determine working directory
    local working_dir=$(dirname "$procfile")
    echo "📂 Using working directory: $working_dir"

    # Extract web process command
    local command=$(grep "^web:" "$procfile" | cut -d':' -f2- | sed 's/^[ \t]*//')
    if [ -z "$command" ]; then
        echo "❌ No web process found in Procfile"
        exit 1
    fi
    echo "🚀 Detected command: $command"

    # Auto-detect port (supports most common formats)
    local detected_port=$(
        echo "$command" | grep -oE '\b(--port|-p|PORT=)[ =]?[0-9]+\b' | 
        grep -oE '[0-9]+' | head -1
    )
    echo "🔌 Auto-detected port: ${detected_port:-none}"

    # Create systemd service
    echo "📝 Creating service file..."
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

    # Enable and start service
    echo "⚡ Starting service..."
    sudo systemctl daemon-reload
    sudo systemctl enable "${REPO_NAME}"
    sudo systemctl restart "${REPO_NAME}"

    # Verify service status
    echo "🔄 Verifying service..."
    for i in {1..5}; do
        if sudo systemctl is-active --quiet "${REPO_NAME}"; then
            echo "✅ Service started successfully"
            return 0
        fi
        sleep 2
    done

    echo "❌ Failed to start service"
    echo "📜 Last logs:"
    journalctl -u "${REPO_NAME}" -n 20 --no-pager
    exit 1
}

# ----------------------------
# MAIN EXECUTION
# ----------------------------
echo "📁 Starting deployment for: $APP_DIR"
install_runtime
create_service

echo "🎉 Deployment completed successfully!"
echo "🔍 Service status: sudo systemctl status ${REPO_NAME}"
echo "📜 View logs: journalctl -u ${REPO_NAME} -f"
