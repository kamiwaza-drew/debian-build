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


GITHUB_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test"

# If github directory does not exist, create it. If it exists, remove it.
if [ ! -d "$GITHUB_DIR" ]; then
    mkdir -p "$GITHUB_DIR"
else
    sudo rm -rf "$GITHUB_DIR"
fi

# Directories to store offline packages
PYTHON_WHEELS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_python_wheels"
DEB_PACKAGES_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_debs"
COCKROACH_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_cockroach"
CUDA_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_cuda"
NODEJS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_nodejs"
DOCKER_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_docker"


mkdir -p "$PYTHON_WHEELS_DIR" "$DEB_PACKAGES_DIR" "$COCKROACH_DIR" "$CUDA_DIR" "$NODEJS_DIR" "$DOCKER_DIR"

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


# ############################## START CLONING REPOSITORIES
# Clone the Kamiwaza Deploy repository
log_info "Cloning Kamiwaza Deploy repository..."
cd "$GITHUB_DIR"
if [ ! -d "kamiwaza-deploy" ]; then
    git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza-deploy.git
else
    log_info "Kamiwaza Deploy repository already exists. Checking out branch $GIT_BRANCH."
    cd kamiwaza-deploy
    git fetch origin
    git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH" origin/"$GIT_BRANCH"
    git pull origin "$GIT_BRANCH"
    cd "$GITHUB_DIR"
fi

# Clone the Kamiwaza repository inside kamiwaza-deploy
log_info "Cloning Kamiwaza Core repository..."
cd "$GITHUB_DIR"/kamiwaza-deploy
if [ ! -d "kamiwaza" ]; then
    git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza.git
else
    log_info "Kamiwaza Core repository already exists. Checking out branch $GIT_BRANCH."
    cd kamiwaza
    git fetch origin
    git checkout "$GIT_BRANCH" || git checkout -b "$GIT_BRANCH" origin/"$GIT_BRANCH"
    git pull origin "$GIT_BRANCH"
    cd "$GITHUB_DIR"/kamiwaza-deploy
fi

# Ensure wheel and build tools are available on dev's machine
pip install --upgrade pip setuptools wheel

# Build Python wheels for requirements.txt
echo "Building Python wheels for requirements.txt..."
pip wheel -r "$GITHUB_DIR"/kamiwaza-deploy/requirements.txt -w "$PYTHON_WHEELS_DIR"


# ############################## START DOWNLOADING .DEB PACKAGES
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

sudo apt update
sudo apt install --download-only -y -o=dir::cache="$DEB_PACKAGES_DIR" "${DEB_PACKAGES[@]}"
sudo find "$DEB_PACKAGES_DIR/archives/" -name "*.deb" -exec mv {} "$DEB_PACKAGES_DIR" \; 2>/dev/null || true
sudo rm -rf "$DEB_PACKAGES_DIR/archives"
sudo chown -R $USER:$USER "$DEB_PACKAGES_DIR"


# ############################## START DOWNLOADING TARBALLS
# 3. Download CockroachDB tarball
echo "Downloading CockroachDB tarball..."
curl -L -o "$COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz" https://binaries.cockroachdb.com/cockroach-v24.1.0.linux-amd64.tgz

# 4. Download Node.js tarball (optional, for offline Node.js install)
echo "Downloading Node.js v18 tarball..."
curl -L -o "$NODEJS_DIR/node-v18.x-linux-x64.tar.xz" https://nodejs.org/dist/v18.20.3/node-v18.20.3-linux-x64.tar.xz

# 5. Download Docker and Docker Compose .deb files
echo "Downloading Docker and Docker Compose .deb files..."
curl -L -o "$DOCKER_DIR/docker-26.0.7.tgz" https://download.docker.com/linux/static/stable/x86_64/docker-26.0.7.tgz
curl -L -o "$DOCKER_DIR/docker-compose-linux-x86_64" https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64

# # 6. Download CUDA .deb (optional, if you want to support CUDA offline)
# # Example: libtinfo5
# echo "Downloading libtinfo5 .deb..."
# wget -O "$CUDA_DIR/libtinfo5_6.4-2_amd64.deb" http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb


# ############################## START VERIFICATION
# 7. Verify all required files are present
echo "Verifying all required files are present..."

verify_files() {
    local errors=0
    
    # Run all checks in parallel
    {
        if [ ! "$(ls -A "$PYTHON_WHEELS_DIR"/*.whl 2>/dev/null)" ]; then
            log_error "ERROR: No Python wheels found in $PYTHON_WHEELS_DIR"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! "$(ls -A "$DEB_PACKAGES_DIR"/*.deb 2>/dev/null)" ]; then
            log_error "ERROR: No deb packages found in $DEB_PACKAGES_DIR"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! -f "$COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz" ]; then
            log_error "ERROR: CockroachDB tarball not found at $COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! "$(ls -A "$CUDA_DIR"/*.deb 2>/dev/null)" ]; then
            log_error "ERROR: No CUDA packages found in $CUDA_DIR"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! -f "$NODEJS_DIR/node-v18.x-linux-x64.tar.xz" ]; then
            log_error "ERROR: Node.js tarball not found at $NODEJS_DIR/node-v18.x-linux-x64.tar.xz"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! -f "$DOCKER_DIR/docker-26.0.7.tgz" ] || [ ! -f "$DOCKER_DIR/docker-compose-linux-x86_64" ]; then
            log_error "ERROR: Docker files missing in $DOCKER_DIR"
            errors=$((errors + 1))
        fi
    } &

    {
        if [ ! -d "$GITHUB_DIR/kamiwaza-deploy" ]; then
            log_error "ERROR: kamiwaza-deploy folder not found at $GITHUB_DIR/kamiwaza-deploy"
            errors=$((errors + 1))
        fi
    } &

    # Wait for all background processes to complete
    wait

    # Return the error count
    return $errors
}

# Run verification and store the result
verify_files
VERIFY_STATUS=$?

if [ $VERIFY_STATUS -gt 0 ]; then
    log_error "Verification failed with $VERIFY_STATUS errors. Please fix the issues above."
    exit 1
fi

log_info "All required files have been downloaded for offline installation."



# ############################## START PACKAGING THE INSTALLER
package_files() {
    local start_time=$(date +%s)
    local build_dir="$GITHUB_DIR/.."
    local exit_code=0

    cd "$build_dir" || {
        log_error "Failed to change directory to $build_dir"
        return 1
    }

    # Create a lockfile to prevent multiple builds
    if [ -f ".packaging.lock" ]; then
        log_error "Another packaging process is running. If this is incorrect, remove .packaging.lock"
        return 1
    }
    touch .packaging.lock

    # Cleanup function
    cleanup() {
        rm -f .packaging.lock
        if [ $exit_code -ne 0 ]; then
            log_error "Packaging failed. Check the logs above for details."
        fi
    }
    trap cleanup EXIT

    log_info "Starting package build process..."
    
    # Use parallel compression if available
    if command -v pigz > /dev/null; then
        export COMPRESSION_COMMAND="pigz"
    else
        export COMPRESSION_COMMAND="gzip"
    fi
    
    # Set environment variables for faster builds
    export DEB_BUILD_OPTIONS="parallel=$(nproc)"
    
    # Build the package
    if ! dpkg-buildpackage -us -uc -rfakeroot; then
        exit_code=1
        return 1
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "Package built successfully in $duration seconds"
    
    # Verify the built package
    if ! dpkg-deb --info ../*.deb >/dev/null 2>&1; then
        log_error "Package verification failed"
        exit_code=1
        return 1
    fi
    
    log_info "Package verified successfully"
    return 0
}

# Check if --full flag was passed or ask for user input
if [[ "$*" == *"--full"* ]] || [[ "$PACKAGE_CHOICE" == "y" ]]; then
    cd "$GITHUB_DIR"
    log_info "Packaging the files into a deb package..."
    
    if ! package_files; then
        log_error "Failed to create package"
        exit 1
    fi
    
    log_info "Deb package created successfully in $(realpath ..)"
fi
