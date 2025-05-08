#!/bin/bash

# Universal Nginx Config Generator
# Synced with setup-runtime.sh's structure

# ----------------------------
# VALIDATION CHECKS
# ----------------------------
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run with sudo privileges"
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx not installed. Install with: sudo apt install nginx"
    exit 1
fi

[ ! -d "/etc/nginx/conf.d" ] && mkdir -p /etc/nginx/conf.d/

# ----------------------------
# ARGUMENT PARSING
# ----------------------------
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <file-name> <ip/domain> <frontend:yes/no> <frontend-route> <frontend-port> <backend:yes/no> <backend-route> <backend-port>"
    exit 1
fi

FILE_NAME="$1"
DOMAIN="$2"
FRONTEND_PRESENT="$3"
FRONTEND_ROUTE="$4"
FRONTEND_PORT="$5"
BACKEND_PRESENT="$6"
BACKEND_ROUTE="$7"
BACKEND_PORT="$8"

OUTPUT_FILE="/etc/nginx/conf.d/${FILE_NAME}.conf"
APP_DIR="/root/$(basename "$FILE_NAME" .conf)"

# ----------------------------
# SERVICE VERIFICATION (WITH RETRIES)
# ----------------------------
check_service() {
    local port=$1
    local service_type=$2
    
    echo "🔍 Checking $service_type service on port $port..."
    for attempt in {1..3}; do
        if nc -z -w 2 localhost "$port"; then
            echo "✅ $service_type service ready on port $port"
            return 0
        fi
        echo "⚠️ Attempt $attempt: Service not responding (waiting 2s...)"
        sleep 2
    done
    
    echo "❌ Critical: $service_type service failed to start on port $port"
    echo "Debug information:"
    echo "1. Service status:"
    sudo systemctl list-units | grep "$(basename "$FILE_NAME")" || true
    echo "2. Port usage:"
    sudo ss -tulnp | grep ":$port" || true
    echo "3. Process tree:"
    ps auxf | grep -i "$(basename "$FILE_NAME")" || true
    exit 1
}

[ "$FRONTEND_PRESENT" == "yes" ] && check_service "$FRONTEND_PORT" "Frontend"
[ "$BACKEND_PRESENT" == "yes" ] && check_service "$BACKEND_PORT" "Backend"

# ----------------------------
# CONFIG GENERATION
# ----------------------------
generate_config() {
    local BUILD_DIR=""
    if [ "$FRONTEND_PRESENT" == "yes" ]; then
        BUILD_DIR=$(find "$APP_DIR" -type d \( -name "dist" -o -name "build" -o -name "out" -o -name "public" \) -exec test -f {}/index.html \; -print -quit 2>/dev/null)
        [ -n "$BUILD_DIR" ] && echo "🔍 Found build directory: $BUILD_DIR"
    fi

    cat > "$OUTPUT_FILE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 100M;

    location /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }
EOF

    if [ "$FRONTEND_PRESENT" == "yes" ]; then
        if [ -n "$BUILD_DIR" ]; then
            cat >> "$OUTPUT_FILE" <<EOF
    root $BUILD_DIR;
    index index.html;
    location $FRONTEND_ROUTE {
        try_files \$uri \$uri/ /index.html;
    }
EOF
        else
            cat >> "$OUTPUT_FILE" <<EOF
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
EOF
        fi
    fi

    if [ "$BACKEND_PRESENT" == "yes" ]; then
        cat >> "$OUTPUT_FILE" <<EOF
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
EOF
    fi

    cat >> "$OUTPUT_FILE" <<EOF
    # Security Headers
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;";
}
EOF
}

# ----------------------------
# MAIN EXECUTION
# ----------------------------
generate_config

if nginx -t; then
    systemctl restart nginx
    echo "✅ Nginx config created at $OUTPUT_FILE"
    echo "🌐 Access at: http://$DOMAIN"
    echo "💡 Debug: sudo tail -f /var/log/nginx/error.log"
else
    echo "❌ Nginx config test failed:"
    sudo nginx -T | grep -A5 "error"
    exit 1
fi
