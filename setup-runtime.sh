#!/bin/bash

# Universal runtime setup with Procfile and PM2 support

REPO_NAME="$1"
APP_DIR="/root/$REPO_NAME"
RUNTIME_FILE="$APP_DIR/runtime.txt"
PROCFILE="$APP_DIR/Procfile"

# Load deployment config
[ -f "$APP_DIR/.deployment" ] && source "$APP_DIR/.deployment" || {
    echo "BUILD_TYPE=auto" > "$APP_DIR/.deployment"
    echo "DEPLOYMENT_ROOT=$APP_DIR" >> "$APP_DIR/.deployment"
}

# Install from runtime.txt if exists
install_runtimes() {
    if [ -f "$RUNTIME_FILE" ]; then
        echo "🔍 Installing from runtime.txt..."
        while read -r line; do
            case $line in
                nodejs-*)
                    version=${line#nodejs-}
                    echo "⚡ Installing Node.js $version..."
                    curl -fsSL "https://deb.nodesource.com/setup_$version.x" | sudo -E bash -
                    sudo apt-get install -y nodejs
                    ;;
                python-*)
                    version=${line#python-}
                    echo "🐍 Installing Python $version..."
                    sudo apt-get install -y "python$version" "python$version-venv"
                    ;;
                java-*)
                    version=${line#java-}
                    echo "☕ Installing Java $version..."
                    sudo apt-get install -y "openjdk-$version-jdk"
                    ;;
                ruby-*)
                    version=${line#ruby-}
                    echo "💎 Installing Ruby $version..."
                    sudo apt-get install -y "ruby$version"
                    ;;
                *)
                    echo "⚠️ Unknown runtime: $line"
                    ;;
            esac
        done < "$RUNTIME_FILE"
    fi
}

# Process Procfile with PM2
process_procfile() {
    if [ -f "$PROCFILE" ]; then
        echo "🔍 Found Procfile - processing with PM2..."
        
        # Install project dependencies if package.json exists
        if [ -f "$APP_DIR/package.json" ]; then
            echo "📦 Installing Node.js dependencies..."
            npm install --prefix "$APP_DIR"
        fi

        # Process each line in Procfile
        while read -r line; do
            if [[ $line == web:* ]]; then
                process_name="web"
                command="${line#web: }"
            elif [[ $line == worker:* ]]; then
                process_name="worker"
                command="${line#worker: }"
            else
                process_name="process-$((RANDOM % 1000))"
                command="$line"
            fi

            echo "🚀 Starting $process_name with PM2: $command"
            pm2 start "$command" --name "$REPO_NAME-$process_name" --cwd "$APP_DIR"
        done < "$PROCFILE"

        # Save PM2 process list
        pm2 save
        pm2 startup
        echo "PM2 startup command:"
        eval "pm2 startup | tail -n 1"
        
    else
        echo "ℹ️ No Procfile found - checking for common project types..."
        
        # Auto-detect common project types
        if [ -f "$APP_DIR/package.json" ]; then
            echo "📦 Node.js project detected"
            if grep -q '"start"' "$APP_DIR/package.json"; then
                echo "🚀 Starting Node.js app with PM2"
                pm2 start "npm start" --name "$REPO_NAME" --cwd "$APP_DIR"
                pm2 save
            fi
        fi
    fi
}

# Main
cd "$APP_DIR" || exit 1

install_runtimes
process_procfile

# Final permissions
sudo chown -R $USER:www-data "$APP_DIR"
sudo chmod -R 775 "$APP_DIR"

echo "✅ Runtime setup complete"
echo "🔍 PM2 Process List:"
pm2 list
