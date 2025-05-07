#!/bin/bash

# Universal Deployment Script with Systemd Service Support
# Handles: Node.js, Python, Ruby, Java projects
# Features: Auto-restart, proper logging, subfolder detection

REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"
RUNTIME_FILE="$APP_DIR/runtime.txt"
PROCFILE="$APP_DIR/.deployment"

# Load deployment config or create default
[ -f "$APP_DIR/.deployment" ] && source "$APP_DIR/.deployment" || {
    echo "BUILD_TYPE=auto" > "$APP_DIR/.deployment"
    echo "DEPLOYMENT_ROOT=$APP_DIR" >> "$APP_DIR/.deployment"
}

# ----------------------------
# INSTALL RUNTIMES
# ----------------------------
install_runtimes() {
    if [ -f "$RUNTIME_FILE" ]; then
        echo "🔍 Installing from runtime.txt..."
        while read -r line; do
            case $line in
                nodejs-*)
                    version=${line#nodejs-}
                    echo "⚡ Installing Node.js $version..."
                    curl -fsSL "https://deb.nodesource.com/setup_$version.x" | sudo -E bash -
                    sudo apt-get install -y nodejs npm
                    ;;
                python-*)
                    version=${line#python-}
                    echo "🐍 Installing Python $version..."
                    sudo apt-get install -y "python$version" "python$version-venv" python3-pip
                    ;;
                java-*)
                    version=${line#java-}
                    echo "☕ Installing Java $version..."
                    sudo apt-get install -y "openjdk-$version-jdk" maven
                    ;;
                ruby-*)
                    version=${line#ruby-}
                    echo "💎 Installing Ruby $version..."
                    sudo apt-get install -y "ruby$version" ruby-bundler
                    ;;
                *)
                    echo "⚠️ Unknown runtime: $line"
                    ;;
            esac
        done < "$RUNTIME_FILE"
    fi
}

# ----------------------------
# DETECT PROJECT SUBFOLDER
# ----------------------------
detect_app_subfolder() {
    # Priority 1: Check .deployment for custom APP_FOLDER
    if [ -f "$APP_DIR/.deployment" ]; then
        source "$APP_DIR/.deployment"
        if [ -n "$APP_FOLDER" ] && [ -d "$APP_DIR/$APP_FOLDER" ]; then
            APP_SUBFOLDER="$APP_DIR/$APP_FOLDER"
            echo "📂 Using custom folder from .deployment: $APP_FOLDER"
            return
        fi
    fi

    # Priority 2: Auto-detect project root (up to 3 levels deep)
    echo "🔍 Searching for project files..."
    find_project_root() {
        local depth=0
        local max_depth=3
        local current_dir="$1"
        
        while [ "$depth" -le "$max_depth" ]; do
            if [ -f "$current_dir/package.json" ] || 
               [ -f "$current_dir/requirements.txt" ] || 
               [ -f "$current_dir/pom.xml" ] || 
               [ -f "$current_dir/Gemfile" ]; then
                echo "$current_dir"
                return
            fi
            current_dir=$(dirname "$current_dir")
            depth=$((depth + 1))
        done
        echo ""
    }

    detected_dir=$(find_project_root "$APP_DIR")
    if [ -n "$detected_dir" ]; then
        APP_SUBFOLDER="$detected_dir"
        echo "📂 Detected project in: ${APP_SUBFOLDER#$APP_DIR/}"
        return
    fi

    # Priority 3: Manual selection
    echo "❓ No project found in common locations. Available subfolders:"
    ls -d "$APP_DIR"/*/ | sed "s|$APP_DIR/||;s|/||"
    read -p "Enter subfolder name (or press Enter for root): " custom_folder
    
    if [ -n "$custom_folder" ] && [ -d "$APP_DIR/$custom_folder" ]; then
        APP_SUBFOLDER="$APP_DIR/$custom_folder"
        echo "📂 Using manually selected folder: $custom_folder"
        
        # Save to .deployment for future runs
        echo "APP_FOLDER=\"$custom_folder\"" >> "$APP_DIR/.deployment"
    else
        APP_SUBFOLDER="$APP_DIR"
        echo "📂 Defaulting to root directory"
    fi
}

# ----------------------------
# INSTALL PROJECT DEPENDENCIES
# ----------------------------
install_dependencies() {
    echo "📦 Installing project dependencies..."
    
    # Node.js
    if [ -f "$APP_SUBFOLDER/package.json" ]; then
        echo "⚡ Installing Node.js dependencies..."
        npm install --prefix "$APP_SUBFOLDER"
        
        # Build if package.json has build script
        if grep -q '"build"' "$APP_SUBFOLDER/package.json"; then
            echo "🏗️ Building Node.js project..."
            npm run build --prefix "$APP_SUBFOLDER"
        fi
    fi

    # Python
    if [ -f "$APP_SUBFOLDER/requirements.txt" ]; then
        echo "🐍 Installing Python dependencies..."
        pip3 install -r "$APP_SUBFOLDER/requirements.txt"
    fi

    # Ruby
    if [ -f "$APP_SUBFOLDER/Gemfile" ]; then
        echo "💎 Installing Ruby dependencies..."
        bundle install --gemfile "$APP_SUBFOLDER/Gemfile"
    fi

    # Java
    if [ -f "$APP_SUBFOLDER/pom.xml" ]; then
        echo "☕ Building Java project..."
        mvn -f "$APP_SUBFOLDER/pom.xml" clean package
    fi
}

# ----------------------------
# PROCESS PROCFILE (SYSTEMD)
# ----------------------------
create_systemd_service() {
    local service_name="$1"
    local command="$2"
    local working_dir="$3"
    
    echo "🛠️ Creating systemd service: $service_name"
    
    sudo bash -c "cat > /etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=${REPO_NAME} ${service_name}
After=network.target

[Service]
User=root
WorkingDirectory=${working_dir}
ExecStart=/bin/bash -c '${command}'
Restart=always
RestartSec=5
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${service_name}"
    sudo systemctl start "${service_name}"
}

process_procfile() {
    if [ -f "$PROCFILE" ]; then
        echo "🔍 Found Procfile - creating services..."
        
        # Web Process
        if grep -q "^web:" "$PROCFILE"; then
            CMD=$(grep "^web:" "$PROCFILE" | sed 's/web: //')
            create_systemd_service "${REPO_NAME}-web" "$CMD" "$APP_SUBFOLDER"
        fi

        # Worker Process
        if grep -q "^worker:" "$PROCFILE"; then
            CMD=$(grep "^worker:" "$PROCFILE" | sed 's/worker: //')
            create_systemd_service "${REPO_NAME}-worker" "$CMD" "$APP_SUBFOLDER"
        fi
    else
        echo "ℹ️ No Procfile found - attempting auto-start..."
        
        # Node.js fallback
        if [ -f "$APP_SUBFOLDER/package.json" ]; then
            create_systemd_service "${REPO_NAME}" "npm start" "$APP_SUBFOLDER"
        
        # Python fallback
        elif [ -f "$APP_SUBFOLDER/requirements.txt" ]; then
            create_systemd_service "${REPO_NAME}" "gunicorn --bind 0.0.0.0:8000 app:app" "$APP_SUBFOLDER"
        fi
    fi
}

# ----------------------------
# MAIN EXECUTION
# ----------------------------
echo "🚀 Starting deployment for $REPO_NAME"

# 1. Install required runtimes
install_runtimes

# 2. Detect project location
detect_app_subfolder

# 3. Install project dependencies
install_dependencies

# 4. Create systemd services
process_procfile

# 5. Set permissions
sudo chown -R root:www-data "$APP_DIR"
sudo chmod -R 775 "$APP_DIR"

echo "✅ Deployment complete!"
echo "📌 Management commands:"
echo "   sudo systemctl status ${REPO_NAME}*"
echo "   sudo journalctl -u ${REPO_NAME}-web -f"
