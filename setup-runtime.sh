#!/bin/bash

REPO_NAME=$1
APP_DIR="/opt/$REPO_NAME"

echo "🔍 Checking runtime.txt for dependencies..."
RUNTIME_FILE="$APP_DIR/runtime.txt"

if [ -f "$RUNTIME_FILE" ]; then
    while read -r line; do
        SOFTWARE=$(echo "$line" | cut -d'-' -f1)
        VERSION=$(echo "$line" | cut -d'-' -f2)

        case $SOFTWARE in
            nodejs)
                echo "⚡ Installing Node.js v$VERSION..."
                curl -fsSL "https://deb.nodesource.com/setup_$VERSION.x" | bash - || {
                    echo "⚠️ Failed to fetch Node.js setup script. Falling back to default Node.js installation."
                    apt-get update
                    apt-get install -y nodejs npm
                }
                apt-get install -y nodejs npm || echo "⚠️ Node.js installation failed!"
                ;;
            python)
                echo "🐍 Installing Python v$VERSION..."
                apt-get update
                apt-get install -y python$VERSION python$VERSION-venv python$VERSION-dev
                ;;
            java)
                echo "☕ Installing OpenJDK v$VERSION..."
                apt-get update
                apt-get install -y openjdk-$VERSION-jdk
                ;;
            ruby)
                echo "💎 Installing Ruby v$VERSION..."
                apt-get update
                apt-get install -y ruby$VERSION
                ;;
            *)
                echo "⚠️ Unknown runtime: $SOFTWARE-$VERSION"
                ;;
        esac
    done < "$RUNTIME_FILE"
else
    echo "⚠️ No runtime.txt found, skipping runtime setup."
fi

echo "📦 Installing project dependencies..."
cd "$APP_DIR"

# Ensure npm is available before running npm install
if [ -f "package.json" ]; then
    if ! command -v npm &> /dev/null; then
        echo "⚠️ npm is not installed! Installing manually..."
        apt-get install -y npm
    fi
    echo "📦 Running npm install..."
    npm install || echo "⚠️ npm install failed!"
fi

if [ -f "requirements.txt" ]; then
    echo "🐍 Running pip install..."
    python -m pip install -r requirements.txt || echo "⚠️ pip install failed!"
fi

if [ -f "pom.xml" ]; then
    echo "☕ Running Maven install..."
    mvn clean install || echo "⚠️ Maven build failed!"
fi

echo "🔍 Checking Procfile for start command..."
PROCFILE="$APP_DIR/Procfile"

if [ -f "$PROCFILE" ]; then
    START_COMMAND=$(grep '^web:' "$PROCFILE" | sed 's/web: //')
    if [ -n "$START_COMMAND" ]; then
        echo "🚀 Running: $START_COMMAND"
        eval "$START_COMMAND"
    else
        echo "⚠️ No valid start command found in Procfile."
    fi
else
    echo "⚠️ No Procfile found!"
fi

