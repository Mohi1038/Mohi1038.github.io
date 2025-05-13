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

# Validate inputs
if [ "$FRONTEND_PRESENT" != "yes" ] && [ "$FRONTEND_PRESENT" != "no" ]; then
  echo "❌ Frontend presence must be 'yes' or 'no'"
  exit 1
fi

if [ "$BACKEND_PRESENT" != "yes" ] && [ "$BACKEND_PRESENT" != "no" ]; then
  echo "❌ Backend presence must be 'yes' or 'no'"
  exit 1
fi

if [ "$FRONTEND_PRESENT" == "yes" ] && ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Frontend port must be numeric."
  exit 1
fi

if [ "$BACKEND_PRESENT" == "yes" ] && ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]]; then
  echo "❌ Backend port must be numeric."
  exit 1
fi

# Backup existing config if it exists
if [ -f "$CONF_PATH" ]; then
  BACKUP_PATH="/etc/nginx/conf.d/$FILE_NAME.conf.bak_$(date +%Y%m%d%H%M%S)"
  cp "$CONF_PATH" "$BACKUP_PATH"
  echo "⚠️ Existing config backed up to $BACKUP_PATH"
fi

# Write the base server block
cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
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
        proxy_pass http://127.0.0.1:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        
        # For SPA fallback
        try_files \$uri \$uri/ /index.html;
    }
EOF
fi

# Add backend route if applicable
if [ "$BACKEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

    # Backend configuration
    location $BACKEND_ROUTE {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        
        # Increase timeout for backend APIs if needed
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }
EOF
fi

# Close server block
cat >> "$CONF_PATH" <<EOF

    # Static files cache (1 year)
    location ~* \.(?:jpg|jpeg|gif|png|ico|css|js|svg|woff2)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    # Deny access to hidden files
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
  if [ -n "$BACKUP_PATH" ]; then
    echo "⚠️ Restoring backup configuration..."
    mv "$BACKUP_PATH" "$CONF_PATH"
    nginx -t && systemctl reload nginx
  fi
  exit 1
fi

echo -e "\n🔄 Reloading Nginx..."
systemctl reload nginx

echo -e "\n🎉 Nginx successfully reloaded with new configuration!"
echo "📝 Logs can be found at:"
echo "   - /var/log/nginx/${FILE_NAME}_error.log"
echo "   - /var/log/nginx/${FILE_NAME}_access.log"
