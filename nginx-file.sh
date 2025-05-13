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
  echo "Example: $0 demo yourdomain.com yes / 5173 yes /api 3000"
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

# Validate that ports are numbers if they are present
# For frontend
if [ "$FRONTEND_PRESENT" == "yes" ] && ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Frontend port must be a numeric value."
    exit 1
fi

# For backend
if [ "$BACKEND_PRESENT" == "yes" ] && ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Backend port must be a numeric value."
    exit 1
fi

# Write the base server block
cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Enable compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 1024;
    gzip_proxied any;

    # Error handling
    error_log /var/log/nginx/${FILE_NAME}_error.log warn;
    access_log /var/log/nginx/${FILE_NAME}_access.log;

    client_max_body_size 100M;
EOF

# Add frontend route if applicable
if [ "$FRONTEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

    # Frontend configuration
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
EOF
fi

# Add backend route if applicable
if [ "$BACKEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

    # Backend configuration
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
EOF
fi

# Deny access to hidden files
cat >> "$CONF_PATH" <<EOF
    location ~ /\. {
        deny all;
    }
}
EOF

# Test and reload nginx
echo -e "\n✅ Nginx config written to $CONF_PATH"
echo -e "\n🔍 Configuration file content:"
cat "$CONF_PATH"

echo -e "\n🚀 Testing Nginx configuration..."
if ! nginx -t; then
  echo -e "\n❌ Nginx configuration test failed. Please check the errors above."
  exit 1
fi

echo -e "\n🔄 Reloading Nginx..."
systemctl reload nginx

echo -e "\n🎉 Nginx successfully reloaded with new configuration!"
echo "📝 Logs can be found at:"
echo "   - /var/log/nginx/${FILE_NAME}_error.log"
echo "   - /var/log/nginx/${FILE_NAME}_access.log"
