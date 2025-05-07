#!/bin/bash

# Universal Nginx Config Generator (Fixed 502 Errors)
# Maintains original argument format while adding reliability

# ----------------------------
# VALIDATION CHECKS
# ----------------------------
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run with sudo privileges to write to /etc/nginx/conf.d/"
    exit 1
fi

if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx is not installed. Please install Nginx first."
    exit 1
fi

[ ! -d "/etc/nginx/conf.d" ] && mkdir -p /etc/nginx/conf.d/

# ----------------------------
# ARGUMENT PARSING (Original Format)
# ----------------------------
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <file-name> <ip/domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>"
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

OUTPUT_FILE="/etc/nginx/conf.d/$FILE_NAME.conf"
APP_DIR="/root/$(basename "$FILE_NAME" .conf)"

# ----------------------------
# 502 ERROR FIXES
# ----------------------------
# 1. Verify backend services are running before configuring Nginx
check_service() {
    local port=$1
    local service_type=$2
    
    if ! nc -z localhost $port &>/dev/null; then
        echo "❌ Critical: $service_type service not running on port $port"
        echo "   Fix this before proceeding by checking:"
        echo "   sudo systemctl list-units | grep $FILE_NAME"
        exit 1
    fi
}

[ "$FRONTEND_PRESENT" == "yes" ] && check_service $FRONTEND_PORT "Frontend"
[ "$BACKEND_PRESENT" == "yes" ] && check_service $BACKEND_PORT "Backend"

# 2. Add health check endpoints
generate_health_check() {
    echo "    location /health {"
    echo "        access_log off;"
    echo "        return 200 'OK';"
    echo "        add_header Content-Type text/plain;"
    echo "    }"
}

# 3. Enhanced proxy settings
generate_proxy_settings() {
    local port=$1
    local route=$2
    local service_type=$3
    
    cat <<EOF
    location $route {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # 502 Error Fixes:
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        proxy_connect_timeout 300s;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
EOF
}

# ----------------------------
# CONFIG GENERATION
# ----------------------------
{
echo "server {"
echo "    listen 80;"
echo "    listen [::]:80;"
echo "    server_name $DOMAIN;"
echo "    client_max_body_size 100M;"

# Health check endpoint
generate_health_check

# Frontend handling
if [ "$FRONTEND_PRESENT" == "yes" ]; then
    if [ -n "$BUILD_DIR" ] && [ -d "$BUILD_DIR" ]; then
        echo "    root $BUILD_DIR;"
        echo "    index index.html;"
        echo "    location $FRONTEND_ROUTE {"
        echo "        try_files \$uri \$uri/ /index.html;"
        echo "    }"
    else
        generate_proxy_settings $FRONTEND_PORT $FRONTEND_ROUTE "Frontend"
    fi
fi

# Backend handling
if [ "$BACKEND_PRESENT" == "yes" ]; then
    generate_proxy_settings $BACKEND_PORT $BACKEND_ROUTE "Backend"
fi

# Security headers
echo "    # Enhanced security headers"
echo "    add_header X-Frame-Options \"DENY\";"
echo "    add_header X-Content-Type-Options \"nosniff\";"
echo "    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;\";"
echo "    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;"
echo "}"
} > "$OUTPUT_FILE"

# ----------------------------
# DEPLOYMENT
# ----------------------------
if nginx -t; then
    systemctl restart nginx  # Using restart instead of reload for more reliability
    echo "✅ Nginx config created at $OUTPUT_FILE"
    echo "🌐 Access your app at: http://$DOMAIN"
    echo "💡 Debug tips if you see 502 errors:"
    echo "   1. Check service status: sudo systemctl status $(basename "$FILE_NAME" .conf)"
    echo "   2. Verify ports: sudo netstat -tulnp | grep -E '$FRONTEND_PORT|$BACKEND_PORT'"
    echo "   3. Check logs: sudo tail -f /var/log/nginx/error.log"
else
    echo "❌ Nginx configuration test failed. Check errors:"
    sudo nginx -T 2>&1 | grep -A10 -B10 "error"
    exit 1
fi
