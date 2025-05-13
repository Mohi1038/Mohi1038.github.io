#!/bin/bash

# USAGE:
# sudo ./nginx-file.sh <file-name> <domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>

# Example:
# sudo ./nginx-file.sh demo yourdomain.com yes / 5173 yes /api 3000

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run with sudo (root privileges required)"
  exit 1
fi

if ! command -v nginx &>/dev/null; then
  echo "❌ Nginx is not installed"
  exit 1
fi

if [ "$#" -ne 8 ]; then
  echo "Usage: $0 <file-name> <domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>"
  exit 1
fi

FILE_NAME=$1
DOMAIN=$2
FRONTEND_PRESENT=$3
FRONTEND_ROUTE=$4
FRONTEND_PORT=$5
BACKEND_PRESENT=$6
BACKEND_ROUTE=$7
BACKEND_PORT=$8

CONF_PATH="/etc/nginx/conf.d/$FILE_NAME.conf"

cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
EOF

if [ "$FRONTEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

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

if [ "$BACKEND_PRESENT" == "yes" ]; then
  cat >> "$CONF_PATH" <<EOF

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

cat >> "$CONF_PATH" <<EOF
}
EOF

echo -e "\n✅ Config written to $CONF_PATH"

nginx -t && systemctl reload nginx && echo "🚀 Nginx reloaded successfully"

