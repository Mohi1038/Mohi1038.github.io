#!/bin/bash

# Check if running with sudo privileges
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run with sudo privileges to write to /etc/nginx/conf.d/"
    exit 1
fi

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx is not installed. Please install Nginx first."
    exit 1
fi

# Ensure /etc/nginx/conf.d/ exists
if [ ! -d "/etc/nginx/conf.d" ]; then
    echo "📁 /etc/nginx/conf.d/ directory does not exist. Creating it..."
    mkdir -p /etc/nginx/conf.d/
fi

# Check argument count
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <file-name> <ip/domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>"
    exit 1
fi

# Assign arguments
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

# Load deployment config if it exists
if [ -f "$APP_DIR/.deployment" ]; then
    source "$APP_DIR/.deployment"
fi

# Validate port function
validate_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "❌ Error: Invalid port number '$1'"
        exit 1
    fi
}

[ "$FRONTEND_PRESENT" == "yes" ] && validate_port "$FRONTEND_PORT"
[ "$BACKEND_PRESENT" == "yes" ] && validate_port "$BACKEND_PORT"

# Generate Nginx config
{
echo "server {"
echo "    listen 80;"
echo "    listen [::]:80;"
echo "    server_name $DOMAIN;"
echo "    client_max_body_size 100M;"

# Frontend handling
if [ "$FRONTEND_PRESENT" == "yes" ]; then
    if [ -n "$BUILD_DIR" ] && [ -d "$BUILD_DIR" ]; then
        echo "    root $BUILD_DIR;"
        echo "    index index.html;"
        echo "    location $FRONTEND_ROUTE {"
        echo "        try_files \$uri \$uri/ /index.html;"
        echo "    }"
    else
        echo "    location $FRONTEND_ROUTE {"
        echo "        proxy_pass http://localhost:$FRONTEND_PORT;"
        echo "        proxy_http_version 1.1;"
        echo "        proxy_set_header Upgrade \$http_upgrade;"
        echo "        proxy_set_header Connection 'upgrade';"
        echo "        proxy_set_header Host \$host;"
        echo "        proxy_cache_bypass \$http_upgrade;"
        echo "    }"
    fi
fi

# Backend handling
if [ "$BACKEND_PRESENT" == "yes" ]; then
    echo "    location $BACKEND_ROUTE {"
    echo "        proxy_pass http://localhost:$BACKEND_PORT;"
    echo "        proxy_http_version 1.1;"
    echo "        proxy_set_header Upgrade \$http_upgrade;"
    echo "        proxy_set_header Connection 'upgrade';"
    echo "        proxy_set_header Host \$host;"
    echo "        proxy_set_header X-Real-IP \$remote_addr;"
    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "    }"
fi

# Security headers
echo "    add_header X-Frame-Options \"DENY\";"
echo "    add_header X-Content-Type-Options \"nosniff\";"
echo "    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';\";"
echo "}"
} > "$OUTPUT_FILE"

# Test and reload Nginx
if nginx -t; then
    systemctl reload nginx
    echo "✅ Nginx config created at $OUTPUT_FILE"
    echo "🌐 Access your app at: http://$DOMAIN"
else
    echo "❌ Nginx configuration test failed."
    exit 1
fi

