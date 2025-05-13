#!/bin/bash

# Check if running with sudo privileges to write in /etc/nginx/conf.d/
# because it is protected and require root acces
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
    echo "Usage: $0 <file-name> <ip/domain> <frontend: yes/no> <frontend-route> <frontend-port> <backend: yes/no> <backend-route> <backend-port>"
    exit 1
fi

# Assign input arguments
FILE_NAME=$1
DOMAIN=$2
FRONTEND_PRESENT=$3
FRONTEND_ROUTE=$4
FRONTEND_PORT=$5
BACKEND_PRESENT=$6
BACKEND_ROUTE=$7
BACKEND_PORT=$8

OUTPUT_FILE="/etc/nginx/conf.d/$FILE_NAME.conf"

# Validate that ports are numbers if they are present
if [ "$FRONTEND_PRESENT" == "yes" ] && ! [[ "$FRONTEND_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Frontend port must be a numeric value."
    exit 1
fi

if [ "$BACKEND_PRESENT" == "yes" ] && ! [[ "$BACKEND_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Backend port must be a numeric value."
    exit 1
fi

# Write the Nginx configuration to the file
cat > $OUTPUT_FILE << EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    index index.html;
EOF

if [ "$FRONTEND_PRESENT" == "yes" ]; then
    echo "
    # Frontend app
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        try_files \$uri \$uri/ /index.html;
    }" >> $OUTPUT_FILE
fi

if [ "$BACKEND_PRESENT" == "yes" ]; then
    echo "
    # Backend API requests
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_set_header Host \$host;
    }" >> $OUTPUT_FILE
fi

echo "}" >> $OUTPUT_FILE

# Check if the file was created successfully or not
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Failed to create the Nginx configuration file."
    exit 1
fi

echo "Nginx configuration created at $OUTPUT_FILE"

# Test Nginx configuration for syntax errors
echo "Testing Nginx configuration..."
if ! nginx -t; then
    echo "Nginx configuration test failed. Please check your config."
    exit 1
fi

# Reload Nginx to apply the new configuration
echo "Restarting Nginx..."
if systemctl restart nginx; then
    echo "Nginx restarted successfully."
else
    echo "Failed to restart Nginx. Please check the service status."
    exit 1
fi
