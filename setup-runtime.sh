#!/bin/bash

REPO_NAME=$1
APP_DIR="/root/$REPO_NAME"

echo "🔍 Checking runtime.txt for dependencies..."
RUNTIME_FILE="$APP_DIR/runtime.txt"

if [ -f "$RUNTIME_FILE" ]; then
    while read -r line; do
        SOFTWARE=$(echo "$line" | cut -d'-' -f1)
        VERSION=$(echo "$line" | cut -d'-' -f2)

        case $SOFTWARE in
            nodejs)
                echo "⚡ Installing Node.js v$VERSION..."
                curl -fsSL "https://deb.nodesource.com/setup_$VERSION.x" | sudo -E bash - || {
                    echo "⚠️ Failed to fetch Node.js setup script."
                    exit 1
                }
                sudo apt-get install -y nodejs || {
                    echo "⚠️ Node.js installation failed!"
                    exit 1
                }
                ;;
            python)
                echo "🐍 Installing Python v$VERSION..."
                sudo apt-get update
                sudo apt-get install -y python$VERSION python$VERSION-venv python$VERSION-dev || {
                    echo "⚠️ Python installation failed!"
                    exit 1
                }
                ;;
            java)
                echo "☕ Installing OpenJDK v$VERSION..."
                sudo apt-get update
                sudo apt-get install -y openjdk-$VERSION-jdk || {
                    echo "⚠️ Java installation failed!"
                    exit 1
                }
                ;;
            ruby)
                echo "💎 Installing Ruby v$VERSION..."
                sudo apt-get update
                sudo apt-get install -y ruby$VERSION || {
                    echo "⚠️ Ruby installation failed!"
                    exit 1
                }
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

if [ -f "package.json" ]; then
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
        echo "🚀 Running: $START_COMMAND in the background..."
        nohup bash -c "$START_COMMAND" > /dev/null 2>&1 &
        disown
    else
        echo "⚠️ No valid start command found in Procfile."
    fi
else
    echo "⚠️ No Procfile found!"
fi


