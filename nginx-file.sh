#!/bin/bash

# Universal Nginx Config Generator
# Now fully synchronized with setup-runtime.sh's directory structure

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
# ARGUMENT PARSING
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
# PROJECT STRUCTURE DETECTION (SYNCED WITH SETUP-RUNTIME)
# ----------------------------
find_project_root() {
    local current_dir="$1"
    
    # Look for typical root markers in current directory
    for marker in Procfile runtime.txt package.json requirements.txt Gemfile pom.xml; do
        if [ -f "$current_dir/$marker" ]; then
            echo "$current_dir"
            return 0
        fi
    done
    
    # Check immediate subdirectories if nothing found in root
    for subdir in "$current_dir"/*; do
        if [ -d "$subdir" ]; then
            for marker in Procfile runtime.txt package.json requirements.txt Gemfile pom.xml; do
                if [ -f "$subdir/$marker" ]; then
                    echo "$subdir"
                    return 0
                fi
            done
        fi
    done
    
    # Fallback to provided directory if nothing found
    echo "$current_dir"
}

find_build_dir() {
    local search_dir="$1"
    local build_dirs=("dist" "build" "out" "public" "output")
    
    for dir_name in "${build_dirs[@]}"; do
        # Check direct path first (common case)
        if [ -d "$search_dir/$dir_name" ] && [ -f "$search_dir/$dir_name/index.html" ]; then
            echo "$search_dir/$dir_name"
            return 0
        fi
        
        # Check one level deeper
        while IFS= read -r found_dir; do
            if [ -f "$found_dir/index.html" ]; then
                echo "$found_dir"
                return 0
            fi
        done < <(find "$search_dir" -maxdepth 2 -type d -name "$dir_name" 2>/dev/null | sort)
    done
    
    return 1
}

# ----------------------------
# SERVICE VERIFICATION
# ----------------------------
check_service() {
    local port=$1
    local service_type=$2
    
    if ! nc -z localhost $port &>/dev/null; then
        echo "❌ Critical: $service_type service not running on port $port"
        echo "   Fix this before proceeding:"
        echo "   1. Check service: sudo systemctl list-units | grep $FILE_NAME"
        echo "   2. Verify port: sudo ss -tulnp | grep ':$port'"
        exit 1
    fi
}

[ "$FRONTEND_PRESENT" == "yes" ] && check_service $FRONTEND_PORT "Frontend"
[ "$BACKEND_PRESENT" == "yes" ] && check_service $BACKEND_PORT "Backend"

# ----------------------------
# CONFIG GENERATION
# ----------------------------
generate_health_check() {
    echo "    location /health {"
    echo "        access_log off;"
    echo "        return 200 'OK';"
    echo "        add_header Content-Type text/plain;"
    echo "    }"
}

generate_proxy_settings() {
    local port=$1
    local route=$2
    
    cat <<EOF
    location $route {
        proxy_pass http://localhost:$port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # 502 Error Prevention
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
# MAIN CONFIGURATION
# ----------------------------
# Find actual project root (sync with setup-runtime)
APP_SUBFOLDER=$(find_project_root "$APP_DIR")
echo "📂 Detected project root: $APP_SUBFOLDER"

# Find build directory (prioritizing project root)
BUILD_DIR=""
if [ "$FRONTEND_PRESENT" == "yes" ]; then
    BUILD_DIR=$(find_build_dir "$APP_SUBFOLDER")
    [ -z "$BUILD_DIR" ] && BUILD_DIR=$(find_build_dir "$APP_DIR")
    
    if [ -n "$BUILD_DIR" ]; then
        echo "🔍 Found build directory at: $BUILD_DIR"
    else
        echo "ℹ️ No build directory found - using proxy mode for frontend"
    fi
fi

# Generate config
{
echo "server {"
echo "    listen 80;"
echo "    listen [::]:80;"
echo "    server_name $DOMAIN;"
echo "    client_max_body_size 100M;"

# Health check
generate_health_check

# Frontend configuration
if [ "$FRONTEND_PRESENT" == "yes" ]; then
    if [ -n "$BUILD_DIR" ]; then
        echo "    root $BUILD_DIR;"
        echo "    index index.html;"
        echo "    location $FRONTEND_ROUTE {"
        echo "        try_files \$uri \$uri/ /index.html;"
        echo "    }"
    else
        generate_proxy_settings $FRONTEND_PORT $FRONTEND_ROUTE
    fi
fi

# Backend configuration
if [ "$BACKEND_PRESENT" == "yes" ]; then
    generate_proxy_settings $BACKEND_PORT $BACKEND_ROUTE
fi

# Security headers
echo "    # Security Headers"
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
    systemctl restart nginx
    echo "✅ Nginx config created at $OUTPUT_FILE"
    echo "🌐 Access your app at: http://$DOMAIN"
    echo "💡 Debug tips:"
    echo "   - Service status: sudo systemctl status ${FILE_NAME%.*}"
    echo "   - Ports: sudo ss -tulnp | grep -E ':$FRONTEND_PORT|:$BACKEND_PORT'"
    echo "   - Nginx logs: sudo tail -f /var/log/nginx/error.log"
else
    echo "❌ Nginx configuration test failed:"
    sudo nginx -T 2>&1 | grep -A10 -B10 "error"
    exit 1
fi
