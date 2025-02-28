#!/bin/bash

# Check if running with sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo privileges to write to /etc/nginx/conf.d/"
  exit 1
fi

# Check if Nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "Nginx is not installed. Please install Nginx first."
    exit 1
fi

# Check if /etc/nginx/conf.d/ exists, create it if not
if [ ! -d "/etc/nginx/conf.d" ]; then
    echo "/etc/nginx/conf.d/ directory does not exist. Creating it..."
    mkdir -p /etc/nginx/conf.d/
fi

# Check if enough arguments are passed
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <file-name> <ip/domain> frontend <frontend-route> <frontend-port> backend <backend-route> <backend-port>"
    exit 1
fi

# Assign input arguments
FILE_NAME=$1
DOMAIN=$2
FRONTEND_ROUTE=$4
FRONTEND_PORT=$5
BACKEND_ROUTE=$7
BACKEND_PORT=$8

OUTPUT_FILE="/etc/nginx/conf.d/$FILE_NAME.conf"

# Validate that ports are numbers
if ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]] || ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Ports must be numeric values."
    exit 1
fi

# Write the Nginx configuration to the file
cat > $OUTPUT_FILE << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    index index.html;
    # Frontend app
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        try_files \$uri \$uri/ /index.html;
    }
    # Backend API requests
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_set_header Host \$host;
    }
}
EOF

# Check if the file was created successfully
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Failed to create the Nginx configuration file."
    exit 1
fi

echo "Nginx configuration created at $OUTPUT_FILE"
