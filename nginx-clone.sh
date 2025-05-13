#!/bin/bash

# Check if correct number of arguments are provided
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <git-username> <repo-name> <repo-type> [PAT-token]"
    echo "repo-type: 'public' or 'private'"
    echo "PAT-token is required only for private repositories"
    exit 1
fi

# Store arguments in variables
GIT_USERNAME="$1"
REPO_NAME="$2"
REPO_TYPE="$3"
PAT_TOKEN="$4"

# Validate repository type
if [[ "$REPO_TYPE" != "public" && "$REPO_TYPE" != "private" ]]; then
    echo "Error: Repository type must be 'public' or 'private'"
    exit 1
fi

# Check PAT token for private repositories
if [[ "$REPO_TYPE" == "private" && -z "$PAT_TOKEN" ]]; then
    echo "Error: PAT token is required for private repositories"
    exit 1
fi

# Project directory (stay under /root)
PROJECT_DIR="/root/$REPO_NAME"

# Function to check if a command was successful
check_status() {
    if [ $? -eq 0 ]; then
        echo "$1 successful"
    else
        echo "Error: $1 failed"
        exit 1
    fi
}

# Update package list
echo "Updating package list..."
apt-get update
check_status "Package list update"

# Install required packages
echo "Installing required packages..."
apt-get install -y curl apt-transport-https ca-certificates software-properties-common git nginx
check_status "Required packages installation"

# Start and enable NGINX
echo "Starting NGINX..."
systemctl start nginx
systemctl enable nginx
check_status "NGINX start"

# Creating the project directory
echo "Creating project directory at $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Clone the repository
echo "Cloning repository..."
if [[ "$REPO_TYPE" == "private" ]]; then
    git clone https://${GIT_USERNAME}:${PAT_TOKEN}@github.com/${GIT_USERNAME}/${REPO_NAME}.git .
else
    git clone https://github.com/${GIT_USERNAME}/${REPO_NAME}.git .
fi
check_status "Repository cloning"

# Set permissions so NGINX (www-data) can access everything
echo "Setting permissions..."

# Allow NGINX to traverse /root
chmod +x /root

# Change ownership and permission of the repo
chown -R root:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"

echo "✅ Setup complete! The repository is cloned at $PROJECT_DIR and accessible by NGINX."

