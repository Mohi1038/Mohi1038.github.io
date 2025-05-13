#!/bin/bash

# USAGE:
# sudo ./nginx-file.sh <file-name> <domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>

# Example:
# sudo ./nginx-file.sh demo yourdomain.com yes / 5173 yes /api 3000

if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run with sudo privileges (root access required for /etc/nginx/conf.d/)"
  exit 1
fi

# Check if Nginx is installed
if ! command -v nginx &>/dev/null; then
  echo "❌ Nginx is not installed. Please install Nginx first."
  exit 1
fi

# Validate number of args
if [ "$#" -ne 8 ]; then
  echo "Usage: $0 <file-name> <domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>"
  exit 1
fi

# Input variables
FILE_NAME=$1
DOMAIN=$2
FRONTEND_PRESENT=$3
FRONTEND_ROUTE=$4
FRONTEND_PORT=$5
BACKEND_PRESENT=$6
BACKEND_ROUTE=$7
BACKEND_PORT=$8

CONF_PATH="/etc/nginx/conf.d/$FILE_NAME.conf"

# Validate ports if present
if [ "$FRONTEND_PRESENT" == "yes" ] && ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Frontend port must be numeric."
  exit 1
fi

if [ "$BACKEND_PRESENT" == "yes" ] && ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Backend port must be numeric."
  exit 1
fi

# Write the base server block
cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Enable compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    index index.html;
EOF

# Add frontend route if applicable
if [ "$FRONTEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

    # Frontend reverse proxy
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        try_files \$uri \$uri/ /index.html;
    }
EOF
fi

# Add backend route if applicable
if [ "$BACKEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

    # Backend reverse proxy
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
EOF
fi

# Close server block
echo "}" >> "$CONF_PATH"

# Reload nginx
echo "✅ Nginx config written to $CONF_PATH"
nginx -t && systemctl reload nginx && echo "🔄 Nginx reloaded successfully."

