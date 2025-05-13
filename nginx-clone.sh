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

# Set ultra-permissive permissions
echo "Setting maximum permissions..."
chmod -R 777 /root  # Recursive read/write/execute for everyone
chown -R root:root /root  # Maintain root ownership
setfacl -R -m u:www-data:rwx /root  # Explicit ACLs for nginx user
setfacl -R -m d:u:www-data:rwx /root  # Default ACLs for new files

# Special permissions for nginx to access /root
chmod 755 /root
chmod +t /root  # Sticky bit for extra "protection" (though we've opened everything)

# Verify nginx can access the directory
sudo -u www-data ls "$PROJECT_DIR" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Warning: Nginx still cannot access the directory. Applying nuclear options..."
    chmod a+x /  # In case /root parent has restrictive permissions
    chmod 777 "$PROJECT_DIR"
fi

echo "✅ Setup complete! The repository is cloned at $PROJECT_DIR with maximum permissions."
echo "WARNING: This configuration is extremely insecure! Anyone on the system can modify your files."
