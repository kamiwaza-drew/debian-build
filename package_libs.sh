#!/bin/bash
# Script to download all required Python wheels and .deb packages for offline installation

# Remove set -e to prevent silent failures
# set -e


# Set a variable of the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


GITHUB_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test"

# If github directory does not exist, create it. If it exists, remove it.
if [ ! -d "$GITHUB_DIR" ]; then
    mkdir -p "$GITHUB_DIR"
else
    rm -rf "$GITHUB_DIR"
fi

# Directories to store offline packages
PYTHON_WHEELS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test/offline_python_wheels"
DEB_PACKAGES_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test/offline_debs"
COCKROACH_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test/offline_cockroach"
CUDA_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test/offline_cuda"
NODEJS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/debian/kamiwaza-test/offline_nodejs"


mkdir -p "$PYTHON_WHEELS_DIR" "$DEB_PACKAGES_DIR" "$COCKROACH_DIR" "$CUDA_DIR" "$NODEJS_DIR"


# Prompt for branch selection
echo "Select branch to use for kamiwaza-deploy and kamiwaza:"
echo "1) main (default)"
echo "2) develop"
read -p "Enter your choice (1 or 2): " BRANCH_CHOICE

if [ "$BRANCH_CHOICE" = "2" ]; then
    GIT_BRANCH="develop"
else
    GIT_BRANCH="main"
fi

# Clone the Kamiwaza repository
log_info "Cloning Kamiwaza repository..."
cd "$GITHUB_DIR"
if [ ! -d "kamiwaza-deploy" ]; then
    git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza-deploy.git
else
    log_info "Kamiwaza repository already exists. Checking out branch $GIT_BRANCH."
    cd kamiwaza-deploy
    git fetch origin
    git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH" origin/"$GIT_BRANCH"
    git pull origin "$GIT_BRANCH"
    cd "$GITHUB_DIR"
fi

# Clone the Kamiwaza repository inside kamiwaza-deploy
log_info "Cloning Kamiwaza repository..."
cd "$GITHUB_DIR"/kamiwaza-deploy
if [ ! -d "kamiwaza" ]; then
    git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza.git
else
    log_info "Kamiwaza repository already exists. Checking out branch $GIT_BRANCH."
    cd kamiwaza
    git fetch origin
    git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH" origin/"$GIT_BRANCH"
    git pull origin "$GIT_BRANCH"
    cd "$GITHUB_DIR"/kamiwaza-deploy
fi

# Ensure wheel and build tools are available
pip install --upgrade pip setuptools wheel

# Build Python wheels for requirements.txt
echo "Building Python wheels for requirements.txt..."
pip wheel -r "$GITHUB_DIR"/kamiwaza-deploy/requirements.txt -w "$PYTHON_WHEELS_DIR"


# 2. Download .deb packages for all apt dependencies
# List of required packages (from your install_dependencies function)
DEB_PACKAGES=(
    python3.10
    python3.10-dev
    libpython3.10-dev
    python3.10-venv
    golang-cfssl
    python-is-python3
    etcd-client
    net-tools
    build-essential
    jq
    pkg-config
    libcairo2-dev
    python3-dev
    libgirepository1.0-dev
    python3-gi
    gir1.2-gtk-3.0
    libgirepository-1.0-1
    gobject-introspection
    software-properties-common
)


# To reset:
# sudo dpkg --purge --force-depends kamiwaza
# sudo apt-get -f install
# sudo apt update & sudo  apt upgrade


echo "Downloading .deb packages and dependencies..."

# Then do apt operations
sudo apt update
sudo apt install --download-only -y -o=dir::cache="$DEB_PACKAGES_DIR" "${DEB_PACKAGES[@]}"

# Move downloaded .deb files to the target directory
find "$DEB_PACKAGES_DIR/archives/" -name "*.deb" -exec mv {} "$DEB_PACKAGES_DIR" \; 2>/dev/null || true
rm -rf "$DEB_PACKAGES_DIR/archives"

# 3. Download CockroachDB tarball
echo "Downloading CockroachDB tarball..."
curl -L -o "$COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz" https://binaries.cockroachdb.com/cockroach-v24.1.0.linux-amd64.tgz

# 4. Download CUDA .deb (optional, if you want to support CUDA offline)
# Example: libtinfo5
echo "Downloading libtinfo5 .deb..."
wget -O "$CUDA_DIR/libtinfo5_6.4-2_amd64.deb" http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb

# 5. Download Node.js tarball (optional, for offline Node.js install)
echo "Downloading Node.js v18 tarball..."
curl -L -o "$NODEJS_DIR/node-v18.x-linux-x64.tar.xz" https://nodejs.org/dist/v18.20.3/node-v18.20.3-linux-x64.tar.xz

echo "All required files have been downloaded for offline installation."
