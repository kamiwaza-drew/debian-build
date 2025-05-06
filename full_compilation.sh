
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

# Function to check and fix permissions
check_and_fix_permissions() {
    local dir="$1"
    log_info "Checking permissions for $dir"
    
    # Check if directory exists and is owned by root
    if [ -d "$dir" ] && [ "$(stat -c '%U' "$dir")" = "root" ]; then
        log_warn "Found root-owned directory: $dir"
        log_info "Fixing permissions..."
        sudo chown -R $USER:$USER "$dir"
    fi
}

# Remove set -e to prevent silent failures
# set -e
# Remove any old lock files from all relevant locations
sudo rm -f .packaging.lock
sudo -f kamiwaza-deb/.packaging.lock
sudo -f kamiwaza-deb/kamiwaza-test/.packaging.lock


# Initial permission and cleanup checks
log_info "Performing initial permission and cleanup checks..."

GITHUB_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test"

# If github directory does not exist, create it. If it exists, remove it.
if [ ! -d "$GITHUB_DIR" ]; then
    mkdir -p "$GITHUB_DIR"
else
    sudo rm -rf "$GITHUB_DIR"
fi

# Directories to store offline packages
PYTHON_WHEELS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_python_wheels"
COCKROACH_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_cockroach"
CUDA_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_cuda"
NODEJS_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_nodejs"
DOCKER_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test/offline_docker"


mkdir -p "$PYTHON_WHEELS_DIR" "$COCKROACH_DIR" "$CUDA_DIR" "$NODEJS_DIR" "$DOCKER_DIR"

# Prompt for branch selection
echo "Select branch to use for kamiwaza-deploy and kamiwaza:"
echo "1) main (default)"
echo "2) develop"
read -p "Enter your choice (1 or 2): " BRANCH_CHOICE

if [ "$BRANCH_CHOICE" = "2" ]; then
    GIT_BRANCH="develop"
else
    GIT_BRANCH="master"
fi


# ############################## START CLONING REPOSITORIES
# Clone the Kamiwaza Deploy repository
log_info "Cloning Kamiwaza Deploy repository..."
cd "$GITHUB_DIR"
# Remove existing kamiwaza-deploy directory if it exists
if [ -d "kamiwaza-deploy" ]; then
    log_info "Removing existing Kamiwaza Deploy repository."
    rm -rf "kamiwaza-deploy"
fi

# Clone the repository fresh every time
log_info "Cloning Kamiwaza Deploy repository from branch $GIT_BRANCH..."
git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza-deploy.git

# Clone the Kamiwaza repository inside kamiwaza-deploy
log_info "Cloning Kamiwaza Core repository..."
cd "$GITHUB_DIR"/kamiwaza-deploy
# Remove existing kamiwaza directory if it exists
if [ -d "kamiwaza" ]; then
    rm -rf "kamiwaza"
fi

# if git branch is master, then this is main, otherwise it is develop
if [ "$GIT_BRANCH" = "master" ]; then
    GIT_BRANCH="main"
fi

# Clone the repository fresh every time
git clone --branch "$GIT_BRANCH" https://github.com/m9e/kamiwaza.git


# ============= DEV-ONLY: Overwrite extracted files with /home/kamiwaza/temp_use/ =============
log_info "=== [DEV ONLY] Overwriting extracted files with $SCRIPT_DIR/temp_use/ ==="
cd "$SCRIPT_DIR"
if [ -d "temp_use/" ]; then
    cp -rf temp_use/* "$GITHUB_DIR/kamiwaza-deploy/"
    log_info "[DEV ONLY] Copied files from $SCRIPT_DIR/temp_use/ to $GITHUB_DIR/kamiwaza-deploy/"
else
    log_info "[DEV ONLY] $SCRIPT_DIR/temp_use/ does not exist, skipping dev overwrite."
fi
# ============= END DEV-ONLY =============




# NOW RUN THE PACKAGING SCRIPTS
log_info "Building Docker Images"
bash rebuild.sh

log_info "Ensuring Docker Compose files are present"
bash copy-composer.sh



# Now create a tar.gz archive of kamiwaza-deploy
log_info "Creating kamiwaza-deploy archive..."

# First, create a temporary copy of kamiwaza-deploy to archive
cd "$GITHUB_DIR"
cp -r kamiwaza-deploy kamiwaza-deploy-source
cd "$GITHUB_DIR"/kamiwaza-deploy
# Create the archive in the correct location
tar -czf "$GITHUB_DIR/kamiwaza-deploy/kamiwaza-deploy.tar.gz" .

# Clean up the temporary copy
cd "$GITHUB_DIR"

# Verify the archive was created in the correct location
if [ ! -f "$GITHUB_DIR/kamiwaza-deploy/kamiwaza-deploy.tar.gz" ]; then
    log_error "Failed to create kamiwaza-deploy.tar.gz in the correct location"
    exit 1
fi

sudo rm -rf "$GITHUB_DIR"/kamiwaza-deploy-source

log_info "Successfully created kamiwaza-deploy.tar.gz in kamiwaza-deploy directory"

# Ensure wheel and build tools are available on dev's machine
pip install --upgrade pip setuptools wheel

# Build Python wheels for requirements.txt
echo "Building Python wheels for requirements.txt..."
pip wheel -r "$GITHUB_DIR"/kamiwaza-deploy/requirements.txt -w "$PYTHON_WHEELS_DIR"

# ############################## START DOWNLOADING TARBALLS
# 3. Download CockroachDB tarball
echo "Downloading CockroachDB tarball..."
curl -L -o "$COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz" https://binaries.cockroachdb.com/cockroach-v24.1.0.linux-amd64.tgz

# 4. Download Node.js tarball (optional, for offline Node.js install)
echo "Downloading Node.js v18 tarball..."
curl -L -o "$NODEJS_DIR/node-v18.x-linux-x64.tar.xz" https://nodejs.org/dist/v18.20.3/node-v18.20.3-linux-x64.tar.xz

# 5. Download Docker and Docker Compose .deb files
echo "Downloading Docker and Docker Compose .deb files..."
curl -L -o "$DOCKER_DIR/docker-25.0.3.tgz" https://download.docker.com/linux/static/stable/x86_64/docker-25.0.3.tgz

curl -L -o "$DOCKER_DIR/docker-compose-linux-x86_64" https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-linux-x86_64

# # 6. Download CUDA .deb (optional, if you want to support CUDA offline)
# # Example: libtinfo5
# echo "Downloading libtinfo5 .deb..."
# wget -O "$CUDA_DIR/libtinfo5_6.4-2_amd64.deb" http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb


# Create a temporary directory to store the tar file
mkdir -p "$GITHUB_DIR"/kamiwaza-deploy-temp
# Move the tar file to the temporary directory if it exists
if [ -f "$GITHUB_DIR"/kamiwaza-deploy/kamiwaza-deploy.tar.gz ]; then
    mv "$GITHUB_DIR"/kamiwaza-deploy/kamiwaza-deploy.tar.gz "$GITHUB_DIR"/kamiwaza-deploy-temp/
fi
# Delete all files in the kamiwaza-deploy folder
rm -rf "$GITHUB_DIR"/kamiwaza-deploy/*
# Move the tar file back if it was saved
if [ -f "$GITHUB_DIR"/kamiwaza-deploy-temp/kamiwaza-deploy.tar.gz ]; then
    mv "$GITHUB_DIR"/kamiwaza-deploy-temp/kamiwaza-deploy.tar.gz "$GITHUB_DIR"/kamiwaza-deploy/
fi
# Remove the temporary directory
rm -rf "$GITHUB_DIR"/kamiwaza-deploy-temp



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
        if [ ! -f "$COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz" ]; then
            log_error "ERROR: CockroachDB tarball not found at $COCKROACH_DIR/cockroach-v24.1.0.linux-amd64.tgz"
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
        if [ ! -f "$DOCKER_DIR/docker-25.0.3.tgz" ] || [ ! -f "$DOCKER_DIR/docker-compose-linux-x86_64" ]; then
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

log_info "All required files have been downloaded for offline installation. Please run the bundle-linux.sh script to bundle the files into a single deb package."
