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
            local detected_port=$(echo "$command" | grep -oP '(--port[ =]|-p )\K[0-9]+' | head -1)

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

            sudo systemctl daemon-reload
            sudo systemctl enable "${REPO_NAME}"
            sudo systemctl start "${REPO_NAME}"

            echo "⏳ Waiting for service to start..."

            for attempt in {1..15}; do
                sleep 2
                if sudo systemctl is-active --quiet "${REPO_NAME}"; then
                    if [ -n "$detected_port" ]; then
                        if nc -z localhost "$detected_port"; then
                            echo "✅ Service is active and port $detected_port is listening"
                            return
                        else
                            echo "⏳ Waiting for port $detected_port (attempt $attempt)..."
                        fi
                    else
                        echo "✅ Service is active (no port detected to verify)"
                        return
                    fi
                else
                    echo "⏳ Waiting for service to become active (attempt $attempt)..."
                fi
            done

            echo "❌ Service failed to start or port $detected_port is not listening"
            echo "📜 Last logs:"
            journalctl -u "${REPO_NAME}" -n 15 --no-pager
            exit 1
        fi
    done < "$procfile"

    echo "⚠️ No web process found in Procfile"
    exit 1
}

# ----------------------------
# MAIN
# ----------------------------
echo "📁 Target project: $APP_DIR"
install_runtime
create_service

echo "🎉 Deployment finished!"
echo "📦 To check service: sudo systemctl status $REPO_NAME"
echo "📜 To see logs: journalctl -u $REPO_NAME -f"

