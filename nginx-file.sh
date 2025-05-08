#!/bin/bash

# Universal Nginx Deployment Script
# Supports: JavaScript (React/Vue), Python (Django/Flask), PHP, Static Sites
# Version 3.0 - Full Stack Ready

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
# PERMISSION MANAGEMENT
# ----------------------------
set_universal_permissions() {
    local app_dir="$1"
    local build_dir="$2"
    
    echo "🔒 Setting universal permissions..."
    
    # 1. Secure /root access
    chmod 711 /root
    
    # 2. Base app directory
    chmod 750 "$app_dir"
    chown root:www-data "$app_dir"
    
    # 3. Detect project type and set permissions
    if [ -n "$build_dir" ]; then
        # JavaScript/Node projects
        if [ -f "$app_dir/package.json" ] || [ -f "$build_dir/index.html" ]; then
            echo "📦 Detected JavaScript project"
            chmod -R 750 "$build_dir"
            find "$build_dir" -type f \( -name "*.html" -o -name "*.js" -o -name "*.css" \) -exec chmod 640 {} \;
            [ -d "$build_dir/_next" ] && chmod -R 750 "$build_dir/_next"
        
        # Python projects
        elif [ -f "$app_dir/requirements.txt" ] || [ -f "$app_dir/setup.py" ]; then
            echo "🐍 Detected Python project"
            find "$app_dir" -type f -name "*.py" -exec chmod 750 {} \;
            find "$app_dir" -type d -exec chmod 750 {} \;
            [ -f "$app_dir/manage.py" ] && chmod 750 "$app_dir/manage.py"  # Django
            [ -f "$app_dir/app.py" ] && chmod 750 "$app_dir/app.py"        # Flask/FastAPI
            [ -d "$app_dir/static" ] && chmod -R 750 "$app_dir/static"
            [ -d "$app_dir/templates" ] && chmod -R 750 "$app_dir/templates"
        
        # PHP projects
        elif [ -f "$app_dir/composer.json" ] || [ -f "$build_dir/index.php" ]; then
            echo "🐘 Detected PHP project"
            chmod -R 750 "$build_dir"
            find "$build_dir" -type f -name "*.php" -exec chmod 640 {} \;
        fi
    fi
    
    # 4. Ensure www-data can access
    if ! groups www-data | grep -q '\broot\b'; then
        usermod -aG root www-data
        echo "➕ Added www-data to root group"
    fi
    
    echo "🔍 Final permissions:"
    ls -ld "$app_dir"
    [ -n "$build_dir" ] && ls -ld "$build_dir"
}

# ----------------------------
# SERVICE VERIFICATION
# ----------------------------
verify_service() {
    local port=$1
    local service_name=$2
    
    echo "🔍 Verifying $service_name on port $port..."
    for i in {1..3}; do
        if nc -z -w 2 localhost "$port"; then
            echo "✅ Service active on port $port"
            return 0
        fi
        echo "⏳ Attempt $i/3: Waiting 2s..."
        sleep 2
    done
    
    echo "❌ Service not responding on port $port"
    echo "Debug info:"
    ss -tulnp | grep ":$port" || true
    ps aux | grep -i "$service_name" || true
    exit 1
}

# ----------------------------
# NGINX CONFIG GENERATION
# ----------------------------
generate_nginx_config() {
    local config_file="/etc/nginx/conf.d/${FILE_NAME}.conf"
    local build_dir=$(find "$APP_DIR" -type d \( -name "dist" -o -name "build" -o -name "public" \) -print -quit 2>/dev/null)
    
    echo "📝 Generating Nginx config..."
    
    # Detect project type
    local project_type="proxy"
    [ -f "$APP_DIR/package.json" ] && project_type="javascript"
    [ -f "$APP_DIR/requirements.txt" ] && project_type="python"
    [ -f "$APP_DIR/composer.json" ] && project_type="php"
    
    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 100M;
    
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
EOF

    # Frontend configuration
    if [ "$FRONTEND_ENABLED" = "yes" ]; then
        if [ "$project_type" = "javascript" ] && [ -n "$build_dir" ]; then
            cat >> "$config_file" <<EOF
    root $build_dir;
    index index.html;
    
    location $FRONTEND_ROUTE {
        try_files \$uri \$uri/ /index.html;
    }
EOF
        else
            cat >> "$config_file" <<EOF
    location $FRONTEND_ROUTE {
        proxy_pass http://localhost:$FRONTEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
EOF
        fi
    fi

    # Backend configuration
    if [ "$BACKEND_ENABLED" = "yes" ]; then
        cat >> "$config_file" <<EOF
    location $BACKEND_ROUTE {
        proxy_pass http://localhost:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
EOF
    fi

    # Security headers
    cat >> "$config_file" <<EOF
    add_header X-Frame-Options "DENY";
    add_header X-Content-Type-Options "nosniff";
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'";
}
EOF
}

# ----------------------------
# MAIN EXECUTION
# ----------------------------
if [ "$#" -ne 8 ]; then
    echo "Usage: $0 <config-name> <domain> <frontend:yes/no> <frontend-route> <frontend-port> <backend:yes/no> <backend-route> <backend-port>"
    exit 1
fi

FILE_NAME="$1"
DOMAIN="$2"
FRONTEND_ENABLED="$3"
FRONTEND_ROUTE="$4"
FRONTEND_PORT="$5"
BACKEND_ENABLED="$6"
BACKEND_ROUTE="$7"
BACKEND_PORT="$8"
APP_DIR="/root/$(basename "$FILE_NAME" .conf)"

# Verify services
[ "$FRONTEND_ENABLED" = "yes" ] && verify_service "$FRONTEND_PORT" "frontend"
[ "$BACKEND_ENABLED" = "yes" ] && verify_service "$BACKEND_PORT" "backend"

# Set permissions
BUILD_DIR=$(find "$APP_DIR" -type d \( -name "dist" -o -name "build" -o -name "public" \) -print -quit 2>/dev/null)
set_universal_permissions "$APP_DIR" "$BUILD_DIR"

# Generate config
generate_nginx_config

# Test and restart
if nginx -t; then
    systemctl restart nginx
    echo "✅ Success! Nginx configured for:"
    echo "   Domain: http://$DOMAIN"
    echo "   Frontend: $FRONTEND_ROUTE → port $FRONTEND_PORT"
    echo "   Backend: $BACKEND_ROUTE → port $BACKEND_PORT"
    echo "💡 Debug: sudo tail -f /var/log/nginx/error.log"
else
    echo "❌ Nginx configuration error:"
    nginx -T | grep -A10 "error"
    exit 1
fi
