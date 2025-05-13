#!/bin/bash

REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"
RUNTIME_FILE="$APP_DIR/runtime.txt"
PROCFILE="$APP_DIR/Procfile"

install_runtime() {
    if [ -f "$RUNTIME_FILE" ]; then
        runtime=$(cat "$RUNTIME_FILE")
        case "$runtime" in
            nodejs-*)
                version=$(echo "$runtime" | cut -d'-' -f2)
                curl -fsSL "https://deb.nodesource.com/setup_${version}.x" | bash -
                apt-get install -y nodejs
                ;;

            ruby-*)
                apt-get install -y ruby-full bundler
                ;;

            java-*)
                version=$(echo "$runtime" | cut -d'-' -f2 | tr -d '.')  # 17 -> 17
                apt-get install -y "openjdk-${version}-jdk"
                ;;

            go-*)
                version=$(echo "$runtime" | cut -d'-' -f2)
                curl -fsSL "https://go.dev/dl/go${version}.linux-amd64.tar.gz" | tar -C /usr/local -xz
                echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
                ;;

            php-*)
                version=$(echo "$runtime" | cut -d'-' -f2)  # 8.2 -> 8.2
                apt-get install -y "php${version}" "php${version}-cli" "php${version}-common"
                ;;

            *)
                echo "Unsupported runtime: $runtime"
                exit 1
                ;;
        esac
    fi
}

create_service() {
    local procfile=$(find "$APP_DIR" -maxdepth 2 -name "Procfile" | head -1)
    if [ -z "$procfile" ]; then
        echo "No Procfile found in $APP_DIR or subdirectories"
        exit 1
    fi

    local working_dir=$(dirname "$procfile")
    local command=$(grep "^web:" "$procfile" | cut -d':' -f2- | sed 's/^[ \t]*//')
    if [ -z "$command" ]; then
        echo "No web process found in Procfile"
        exit 1
    fi

    local detected_port=$(
        echo "$command" | grep -oE '\b(--port|-p|PORT=)[ =]?[0-9]+\b' | 
        grep -oE '[0-9]+' | head -1
    )

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
    sudo systemctl restart "${REPO_NAME}"

    for i in {1..5}; do
        if sudo systemctl is-active --quiet "${REPO_NAME}"; then
            return 0
        fi
        sleep 2
    done

    echo "Failed to start service"
    journalctl -u "${REPO_NAME}" -n 20 --no-pager
    exit 1
}

install_runtime
create_service

echo "Service status: sudo systemctl status ${REPO_NAME}"
echo "View logs: journalctl -u ${REPO_NAME} -f"
