#!/usr/bin/bash

# Prevent interactive prompts during installations
export DEBIAN_FRONTEND=noninteractive

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
sudo apt-get update -y
check_status "Package list update"

# Install required packages
echo "Installing required packages..."
sudo apt-get install -y curl apt-transport-https ca-certificates software-properties-common git
check_status "Required packages installation"

# Install NGINX
echo "Installing NGINX..."
sudo apt-get install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx
check_status "NGINX installation"

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
check_status "Docker installation"

# Add current user to Docker group
echo "Adding user to Docker group..."
sudo usermod -aG docker $USER
check_status "User added to Docker group"

# Restart Docker service to apply changes
echo "Restarting Docker service..."
sudo systemctl restart docker
check_status "Docker service restart"

# Install Docker Compose
echo "Installing Docker Compose..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
check_status "Docker Compose installation"

# Create project directory
echo "Creating project directory..."
PROJECT_DIR="/opt/$REPO_NAME"
sudo mkdir -p $PROJECT_DIR
sudo chown $USER:$USER $PROJECT_DIR
cd $PROJECT_DIR

# Clone the repository
echo "Cloning repository..."
if [[ "$REPO_TYPE" == "private" ]]; then
    git clone https://oauth2:${PAT_TOKEN}@github.com/${GIT_USERNAME}/${REPO_NAME}.git .
else
    git clone https://github.com/${GIT_USERNAME}/${REPO_NAME}.git .
fi
check_status "Repository cloning"

# Check if Dockerfile exists
if [[ ! -f "$PROJECT_DIR/Dockerfile" ]]; then
    echo "Error: No Dockerfile found in the repository."
    exit 1
fi

# Build Docker image
echo "Building Docker image..."
sudo docker build -t $REPO_NAME .
check_status "Docker image build"

# Stop and remove any existing container with the same name
echo "Stopping any existing container..."
sudo docker stop $REPO_NAME 2>/dev/null || true
sudo docker rm $REPO_NAME 2>/dev/null || true

# Run Docker container
echo "Running Docker container..."
sudo docker run -d -p 80:80 --name $REPO_NAME $REPO_NAME
check_status "Docker container startup"

# Verify container is running
echo "Verifying container status..."
sudo docker ps

echo "🚀 Deployment completed successfully!"
echo "✔ NGINX is running"
echo "✔ Docker is installed & running"
echo "✔ Docker Compose is installed"
echo "✔ Repository is cloned at $PROJECT_DIR"
echo "✔ Docker image is built and running as a container"
echo "🎯 Visit your deployed application at http://your-server-ip"
