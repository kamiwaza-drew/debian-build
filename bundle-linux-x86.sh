GITHUB_DIR="/home/kamiwaza/debian-packaging/kamiwaza-deb/kamiwaza-test"
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

package_files() {
    local start_time=$(date +%s)
    local build_dir="$GITHUB_DIR/.."
    local exit_code=0

    cd "$build_dir" || {
        log_error "Failed to change directory to $build_dir"
        return 1
    }


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
    if ! sudo dpkg-buildpackage -us -uc -rfakeroot; then
        exit_code=1
        return 1
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_info "Package built successfully in $duration seconds"
    
    # Fix permissions of the output files
    log_info "Fixing permissions of output files..."
    find .. -maxdepth 1 -name "*.deb" -o -name "*.changes" -o -name "*.buildinfo" | while read file; do
        sudo chown $USER:$USER "$file"
    done
    
    # Verify the built package
    if ! dpkg-deb --info ../*.deb >/dev/null 2>&1; then
        log_error "Package verification failed"
        exit_code=1
        return 1
    fi
    
    log_info "Package verified successfully"
    return 0
}

package_files