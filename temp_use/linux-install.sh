#!/bin/bash
# Kamiwaza Installation Script for Ubuntu
# Based on Windows WSL Installation Guide
echo "=== Starting Kamiwaza installation LINNY DREW ==="
set -e  # Exit on error
INSTALL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "Working directory: $(pwd)"


# List of required packages (replace with your actual package names)
REQUIRED_PACKAGES=(
    python3.10
    python3.10-dev
    libpython3.10-dev
    python3.10-venv
    golang-cfssl
    python-is-python3
    etcd-client
    net-tools
    build-essential
    g++
    jq
    libjq1
    pkg-config
    libcairo2-dev
    libcairo-script-interpreter2
    libfontconfig1-dev
    libfreetype6-dev
    libx11-dev
    libxrender-dev
    libxext-dev
    libpng-dev
    libsm-dev
    libpixman-1-dev
    libxcb1-dev
    libxcb-render0-dev
    libxcb-shm0-dev
    libglib2.0-dev
    python3-dev
    libgirepository1.0-dev
    libffi-dev
    python3-gi
    gir1.2-gtk-3.0
    libgirepository-1.0-1
    gobject-introspection
    python3-mako
    python3-markdown
    software-properties-common
)
DEBS_DIR="$INSTALL_DIR/offline_debs"
FIRST_RUN_FLAG="$INSTALL_DIR/.offline_deps_installed"
sudo touch "$FIRST_RUN_FLAG"
sudo chmod 644 "$FIRST_RUN_FLAG"

# Function to check if all dependencies are installed
all_deps_installed() {
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        dpkg -s "$pkg" &>/dev/null || return 1
    done
    return 0
}

# Only run this block if the flag file does not exist
if [ ! -f "$FIRST_RUN_FLAG" ]; then
    if ! all_deps_installed; then
        log_info "Some dependencies are missing. Installing offline .deb dependencies..."
        sudo dpkg -i "$DEBS_DIR"/*.deb || sudo apt-get install -f -y
        # Re-check to ensure all are now installed
        if all_deps_installed; then
            log_info "All dependencies installed successfully."
            touch "$FIRST_RUN_FLAG"
        else
            log_error "Failed to install all dependencies. Please check the .deb files and try again."
            exit 1
        fi
    else
        touch "$FIRST_RUN_FLAG"
    fi
fi




# Save a variable for the current user and directory
current_user=$(whoami)
echo "Current user: $current_user"
export current_user

# Process command-line arguments
NON_INTERACTIVE=false
for arg in "$@"; do
    case "$arg" in
        --non-interactive)
            NON_INTERACTIVE=true
            ;;
    esac
done

# Determine the root directory of this script and export it as INSTALL_DIR
host_ip=$(hostname -I | awk '{print $1}')
export KAMIWAZA_HEAD_IP=$host_ip
export INSTALL_DIR
export host_ip


# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Check for supported distributions
check_distribution() {
    if command_exists lsb_release; then
        distro=$(lsb_release -is)
        if [ "$distro" != "Ubuntu" ]; then
            log_error "This script is designed for Ubuntu. Exiting."
            exit 1
        fi
        log_info "Running on $(lsb_release -ds)"
    elif cat /etc/redhat-release ; then
        log_info "Running on RedHat-based system: $(cat /etc/redhat-release)"
        export IS_REDHAT=true
    else
        log_error "Unsupported distribution. This script requir
        es Ubuntu or RedHat-based systems."
        exit 1
    fi
}

# Wait for package manager lock function
wait_for_package_lock() {
    if [ -d "$INSTALL_DIR/venv" ]; then
        log_info "Found existing virtual environment. Activating it..."
        source "$INSTALL_DIR/venv/bin/activate"
        export VIRTUAL_ENV="$INSTALL_DIR/venv"
    fi

    log_info "Removing any existing package manager locks..."
    
    if [ "$IS_REDHAT" = true ]; then
        # Remove RedHat package manager locks
        sudo rm -f /var/run/yum.pid /var/run/dnf.pid
    else
        # Remove Ubuntu package manager locks
        sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
    fi
    
    log_info "Locks removed, proceeding with installation..."
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to kill processes by port
kill_port_processes() {
    log_info "Killing processes on port 100xx..."
    lsof -iTCP -sTCP:LISTEN -P | grep ':100' | awk '{print $2}' | sort -u | xargs -r kill -9
}

# Function to kill development processes
kill_dev_processes() {
    log_info "Killing Python/Jupyter/Webpack processes..."
    lsof -iTCP -sTCP:LISTEN -P | grep -E 'python|jupyter-l|webpack|node' | awk '{print $2}' | sort -u | xargs -r kill -9
}

# Verify Docker installation
verify_docker() {
    log_info "Verifying Docker installation..."
    
    if ! command_exists docker; then
        log_info "Docker is not installed. Installing Docker..."
        wait_for_package_lock
        
        if [ "$IS_REDHAT" = true ]; then
            # RedHat-based system
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
        else
            # Ubuntu
            log_info "Installing Docker..."
            sudo apt install -y docker.io
        fi
        
        if ! command_exists docker; then
            log_error "Docker installation failed. Please install Docker manually."
            exit 1
        else
            log_info  "Docker successfully installed."
            log_info "Docker version: $(docker --version)"
        fi
    fi

    # Always ensure Docker is enabled and running
    sudo systemctl enable docker
    sudo systemctl start docker

    # Look for docker compose plugin
    if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
        log_info "Docker Compose is not installed. Installing Docker Compose..."
        wait_for_package_lock
        DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
        mkdir -p $DOCKER_CONFIG/cli-plugins
        curl -SL https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
        sudo chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
        log_info "Docker Compose should be installed, testing..."
        if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
            log_error "Docker Compose installation failed. Please install Docker Compose manually."
            exit 1
        else
            log_info "Docker Compose installed successfully."
        fi
    
    else 
        log_info "Docker Compose already installed."
    fi
    
    # Check if user can access Docker daemon
    if ! docker info > /dev/null 2>&1; then
        log_warn "You do not have access to the Docker daemon. Attempting to add you to the 'docker' group..."
        sudo usermod -aG docker $(whoami)
        log_info "Your user $(whoami) has been added to the 'docker' group."
        cd $INSTALL_DIR
    else 
        log_info "You have access to the Docker daemon."
    fi
    
    log_info "Docker version: $(docker --version)"
    
    # Test Docker with hello-world
    log_info "Testing Docker with hello-world..."
    if ! sudo docker run --rm hello-world; then
        log_error "Failed to run hello-world container. Please check Docker setup."
        exit 1
    fi
    
    log_info "Docker is properly installed and configured."
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    if [ "$IS_REDHAT" = true ]; then
        # RedHat-based system
        log_info "Installing dependencies for RedHat-based system..."
        wait_for_package_lock
        sudo yum install -y epel-release
        sudo yum install -y python3.10 python3.10-devel python3.10-pip \
            golang-cfssl etcd net-tools make gcc jq pkgconfig \
            cairo-devel python3-devel
    else
        # Ubuntu
        log_info "Adding deadsnakes PPA and updating package lists..."
        wait_for_package_lock
        sudo add-apt-repository -y ppa:deadsnakes/ppa && sudo apt update
        
        log_info "Installing Python and core dependencies..."

        # List of required packages
        REQUIRED_PACKAGES=(
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
        )

        for pkg in "${REQUIRED_PACKAGES[@]}"; do
            if ! dpkg -s "$pkg" &>/dev/null; then
                log_info "$pkg not found. Installing..."
                sudo apt install -y "$pkg"
            else
                log_info "$pkg already installed. Skipping."
            fi
        done

    fi

    log_info "Installing CockroachDB..."
    if ! command_exists cockroach; then
        cd /tmp
        # Put this into the deb file
        curl -O https://binaries.cockroachdb.com/cockroach-v24.1.0.linux-amd64.tgz
        # on the postinst script, run this:
        tar xzf cockroach-v24.1.0.linux-amd64.tgz
        sudo cp -f cockroach-v24.1.0.linux-amd64/cockroach /usr/local/bin/
        sudo chmod 755 /usr/local/bin/cockroach
        echo "export PATH=/usr/local/bin:\$PATH" >> ~/.bashrc
        sudo sh -c 'echo "Defaults secure_path=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" > /etc/sudoers.d/secure_path'
    else
        log_info "CockroachDB already installed. Skipping download/install."
    fi
    
    log_info "Dependencies installed successfully."
}

# Setup permissions
setup_permissions() {
    log_info "Setting up permissions..."
    
    # Get the current user
    current_user=$(whoami)
    
    # Make certs executable
    log_info "Setting up certificate permissions..."
    if [ -d "$INSTALL_DIR/runtime/etcd/certs" ]; then
        sudo chown -R ${current_user}:${current_user} $INSTALL_DIR/runtime/etcd/certs/* 2>/dev/null || true
        log_info "Certificate permissions updated."
    else
        log_warn "Directory runtime/etcd/certs not found. Skipping permission change."
    fi
    
    # Ensure the current directory is properly owned, ignoring read-only errors
    log_info "Setting ownership of current directory to ${current_user}..."
    sudo chown -R ${current_user}:${current_user} . 2>/dev/null || true
    
    # Optionally make all objects executable
    if [ "$NON_INTERACTIVE" = true ]; then
        # Default to yes for non-interactive mode
        make_executable="y"
    else
        read -p "Make all repository files executable? This is optional but may be needed. [y/N]: " make_executable
    fi
    
    if [[ "$make_executable" == "y" || "$make_executable" == "Y" ]]; then
        log_info "Making all files executable (this may take a moment)..."
        sudo find . -type f -exec chmod +x {} \; 2>/dev/null || true
        log_info "All files are now executable."
    fi
}

# Setup Python environment
setup_python_env() {
    log_info "Setting up Python environment..."
    
    # Check if python3.10 exists, if not install it
    if ! command -v python3.10 &> /dev/null; then
        log_info "Python 3.10 not found. Installing Python 3.10..."
        wait_for_package_lock
        
        if [ "$IS_REDHAT" = true ]; then
            # RedHat-based system
            sudo yum install -y python3.10 python3.10-devel python3.10-pip
        else
            # Ubuntu
            sudo apt update
            wait_for_package_lock
            sudo apt install -y software-properties-common
            sudo add-apt-repository -y ppa:deadsnakes/ppa
            wait_for_package_lock
            sudo apt install -y python3.10 python3.10-dev python3.10-venv
        fi
    fi
    
    # Create and activate virtual environment
    python3.10 -m venv venv
    log_info "Virtual environment created at $INSTALL_DIR/venv. Activating it now..."
    source "$INSTALL_DIR/venv/bin/activate"
    
    # Set Python Path
    export PYTHONPATH="$INSTALL_DIR"
    
    # Install requirements
    log_info "Installing Python requirements..."
    req_path=${req_path:-"$INSTALL_DIR/requirements.txt"}
    pip install -r $req_path
    sudo apt-get install libgirepository1.0-dev
    sudo apt-get install python3-gi
    log_info "Python environment setup complete."
    log_warn "Note: PyGObject may be flagged as a missing dependency, but is not needed for this install."
}

# Set proper permissions for Ray
set_ray_permissions() {
    log_info "Setting proper permissions for Ray..."
    
    # Create Ray temp directory if it doesn't exist
    if [ ! -d "/tmp/ray" ]; then
        sudo mkdir -p /tmp/ray
        log_info "Created /tmp/ray directory"
    fi
    
    # Set ownership and permissions for Ray temp directory for all users
    sudo chown -R $(whoami):$(whoami) /tmp/ray
    sudo chmod -R 777 /tmp/ray
    log_info "Set ownership and permissions for Ray temporary directory for all users"
    
    # Ensure all parent directories have proper permissions
    sudo chmod 777 /tmp
    log_info "Set permissions for /tmp directory"
    
    # Create and set permissions for ~/.ray directory
    mkdir -p ~/.ray
    chmod 777 ~/.ray
    log_info "Set permissions for ~/.ray directory"
}

# Launch Ray
launch_ray() {
    log_info "Launching Ray..."
    
    wait_for_package_lock
    
    
    # Kill ALL possible Ray and Redis processes
    log_info "Killing ALL Ray and Redis processes..."
    ray stop || true
    sudo pkill -9 -f ray || true
    sudo pkill -9 -f redis-server || true
    sudo pkill -9 -f redis || true
    sudo pkill -9 -f raylet || true
    sudo pkill -9 -f plasma_store || true
    sudo pkill -9 -f gcs_server || true
    
    # Remove ALL possible Ray and Redis files
    log_info "Removing ALL Ray and Redis files..."
    sudo rm -rf /tmp/ray || true
    sudo rm -rf ~/.ray || true
    sudo rm -rf /tmp/redis* || true
    sudo rm -rf /var/run/redis* || true
    sudo rm -rf /var/lib/redis* || true
    sudo rm -rf /var/log/redis* || true
    sudo rm -rf /etc/redis* || true
    sudo rm -rf /tmp/plasma* || true
    sudo rm -rf /dev/shm/plasma* || true
    
    # Kill any processes using Ray's ports
    log_info "Killing processes using Ray's ports..."
    for port in 6379 8265 10001 10002 10003 10004 10005; do
        sudo lsof -ti:$port | xargs -r sudo kill -9 || true
    done
    
    # Wait for everything to settle
    sleep 5
    
    # Install fresh Ray and Redis
    log_info "Installing fresh Ray and Redis..."
    # pip install ray==2.9.3 redis==4.6.0 hiredis==3.1.0
    
    # Set proper permissions before starting Ray
    set_ray_permissions
    
    # Use the existing start-ray.sh script
    log_info "Starting Ray using start-ray.sh..."
    # print working directory
    log_info "Current directory: $INSTALL_DIR"
    if [ -f "start-ray.sh" ]; then
        if bash $INSTALL_DIR/start-ray.sh; then
            echo "Ray launched successfully."
        else
            log_error "Ray failed to start. Please try the following:"
            log_error "1. Kill any processes using Ray's ports: 'sudo lsof -ti:8265 | xargs -r sudo kill -9'"
            log_error "2. Check for multiple WSL instances using the required ports"
            log_error "3. On Windows, use 'netstat -ano | findstr :8265' and 'taskkill /F /PID <process_id>'"
            log_error "4. Run 'ray stop' and then 'bash start-ray.sh' manually"
        fi
    else
        echo "$INSTALL_DIR/start-ray.sh script not found."
        exit 1
    fi
}


# Function to start the frontend
setup_frontend() {
    log_info "Starting Kamiwaza frontend..."
    log_info "Current directory: $INSTALL_DIR"
    
    # Ensure npm is installed before starting frontend
    if ! command_exists npm; then
        log_info "npm not found. Installing Node.js and npm..."
        wait_for_package_lock
        sudo apt update
        wait_for_package_lock
        sudo apt install -y nodejs npm
    fi

    # 1. Install nvm (Node Version Manager)
    log_info "Installing nvm..."
    
    # Check if nvm is already installed
    if [ ! -d "$HOME/.nvm" ]; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
        log_info "nvm installed. Setting up environment..."
    else 
        log_info "nvm already installed."
    fi

    # Add NVM to current shell session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
    
    # Install and use Node.js 18
    log_info "Installing and using Node.js 18..."
    nvm install 18
    nvm use 18
    nvm alias default 18

    # 3. Verify
    log_info "Node.js version: $(node --version)"
    log_info "npm version: $(npm --version)"

    # Ensure pm2 is installed before starting frontend
    if ! command_exists pm2; then
        log_info "pm2 not found. Installing pm2 globally..."
        npm install -g pm2
        if ! command_exists pm2; then
            log_warn "pm2 installation with npm failed. Trying with sudo..."
            sudo npm install -g pm2
        fi
    fi

    # if pm2 is running, stop it
    if pm2 list | grep -q "frontend"; then
        log_info "Stopping pm2 frontend..."
        pm2 stop kamiwaza-frontend
    fi
    
    # Ensure the directory has permissions to access all node modules
    if [ -d "$INSTALL_DIR/frontend" ]; then
        log_info "Setting permissions for frontend directory..."
        sudo chown -R $(whoami):$(whoami) "$INSTALL_DIR/frontend"
    fi
    
    if [ "$NON_INTERACTIVE" = true ]; then
        # Default to no for non-interactive mode - don't remove node modules
        reinstall_node_modules="n"
        # Default to no for non-interactive mode - don't run in dev mode
        run_dev_mode="n"
    else
        read -p "Do you want to remove and reinstall node modules? [y/N]: " reinstall_node_modules
        read -p "Do you want to run the frontend in development mode? (yes for dev, anything else for prod) [y/N]: " run_dev_mode
    fi
    
    if [[ "$reinstall_node_modules" == "y" || "$reinstall_node_modules" == "Y" ]]; then
        (cd "$INSTALL_DIR/frontend" && npm cache clean --force && rm -rf node_modules && npm install --no-bin-links)
    fi
    
    if [[ "$run_dev_mode" == "y" || "$run_dev_mode" == "Y" ]]; then
        (cd "$INSTALL_DIR/frontend" && npm install && npm run dev)
    else
        (cd "$INSTALL_DIR/frontend" && npm install && npm run prod)
    fi
}

# Setup environment
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if env.sh already exists
    if [ -f "env.sh" ]; then
        log_info "env.sh already exists. Using existing file."
    else
        # Check if env.sh.example exists
        if [ -f "env.sh.example" ]; then
            cp env.sh.example env.sh
            log_info "Created env.sh from example template."
        else
            log_warn "env.sh.example not found. Creating env.sh manually."
            cat > env.sh << EOL
# Environment variables for Kamiwaza
export KAMIWAZA_RUN_FROM_INSTALL=true
export KAMIWAZA_CLUSTER_MEMBER=true
export KAMIWAZA_INSTALL_ROOT=$(pwd)
export KAMIWAZA_SWARM_HEAD=true
export KAMIWAZA_ORIG_NODE_TYPE=head
export KAMIWAZA_HEAD_IP=127.0.0.1
export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export VIRTUAL_ENV=True
EOL
        fi
    fi
    
    # Source the environment file
    source env.sh
    
    # Run copy-compose script if it exists
    if [ -f "copy-compose.sh" ]; then
        bash copy-compose.sh
        log_info "Ran copy-compose.sh script."
    else
        log_warn "copy-compose.sh not found. Skipping."
    fi
}

# Install Kamiwaza
install_kamiwaza() {
    log_info "Installing Kamiwaza..."
    
    # Create .kamiwaza_install_community file if not exists
    if [ ! -f ".kamiwaza_install_community" ]; then
        touch .kamiwaza_install_community
        log_info "Created .kamiwaza_install_community file."
    fi
    
    # Run installation directly, bypassing WSL check
    log_info "Running installation script..."
    
    proceed_install="y"
    
    # Skip the WSL check and run the core installation
    source set-kamiwaza-root.sh
    source common.sh
    setup_environment
    source "${KAMIWAZA_ROOT:-}/env.sh"

    export USER_ACCEPTED_KAMIWAZA_LICENSE='yes'
    
    # Create and activate virtual environment if needed
    if [[ -z "${VIRTUAL_ENV:-}" ]]; then
        python3.10 -m venv venv
        source venv/bin/activate
    fi
    
    # Fix permissions if needed
    chmod 774 ${KAMIWAZA_ROOT}/startup/kamiwazad.sh || true
    
    # Run the core installation
    export KAMIWAZA_RUN_FROM_INSTALL='yes'


    log_info "########################################################"
    log_info "Step 10: Run first-boot.sh"
    log_info "########################################################"
    
    bash first-boot.sh --head

    log_info "########################################################"
    log_info "Step 11: Run install.py"
    log_info "########################################################"
    python install.py

    unset KAMIWAZA_RUN_FROM_INSTALL
    
    # Fix permissions after installation
    log_info "Fixing permissions after installation..."
    current_user=$(whoami)
    if [ -d "kamiwaza/deployment" ]; then
        sudo chown -R ${current_user}:${current_user} kamiwaza/deployment
    fi
    sudo chown -R ${current_user}:${current_user} .
    
    log_info "Kamiwaza installation completed."
}

# Optional CUDA setup
setup_cuda() {
    if [ "$NON_INTERACTIVE" = true ]; then
        # Skip CUDA in non-interactive mode
        install_cuda="n"
    else
        read -p "Do you want to install CUDA support? [y/N]: " install_cuda
    fi
    
    if [[ "$install_cuda" == "y" || "$install_cuda" == "Y" ]]; then
        log_info "Setting up CUDA..."
        
        # Install libtinfo5
        log_info "Installing libtinfo5..."
        wget http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb
        wait_for_package_lock
        sudo dpkg -i libtinfo5_6.4-2_amd64.deb
        
        # Install CUDA toolkit
        log_info "Installing CUDA toolkit..."
        wait_for_package_lock
        sudo apt install cuda-toolkit-12-4
        
        # Install PyTorch with CUDA support
        log_info "Installing PyTorch with CUDA support..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
        
        # Verify installation
        log_info "Verifying CUDA setup..."
        python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}')"
        python -c "from torchvision.ops import nms; print('NMS OK')"
        
        log_info "CUDA setup completed."
    else
        log_info "CUDA setup skipped."
    fi
}

# Generate self-signed SSL cert for local dev and trust it in Ubuntu
# Generate self-signed SSL cert for local dev and trust it in Ubuntu
generate_ssl_cert() {
    log_info "Generating self-signed SSL certificate..."
    
    # Get hostname for naming the peer certificates
    hostname=$(hostname)
    
    # Write an OpenSSL config with SAN
    cat > cert.cnf << 'EOF'
[ req ]
default_bits        = 2048
prompt              = no
default_md          = sha256
distinguished_name  = dn
req_extensions      = v3_req

[ dn ]
CN = 34.59.53.172

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
IP.1 = 34.59.53.172
DNS.1 = localhost
EOF

    # Generate key and cert
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout server.key \
      -out server.crt \
      -days 365 \
      -config cert.cnf \
      -extensions v3_req

    # Trust the cert system-wide
    log_info "Installing certificate to system trust store..."
    sudo cp server.crt /usr/local/share/ca-certificates/dev-cert.crt
    sudo update-ca-certificates

    # Create etcd certs directory
    log_info "Creating and populating etcd certs directory..."
    mkdir -p "$INSTALL_DIR/runtime/etcd/certs/"
    
    # Copy server.crt as ca.pem and server.key as ca.key for etcd
    cp server.crt "$INSTALL_DIR/runtime/etcd/certs/ca.pem"
    cp server.key "$INSTALL_DIR/runtime/etcd/certs/ca.key"
    
    # Generate peer certificates with the exact naming pattern required by Kamiwaza
    log_info "Generating peer certificates required by Kamiwaza..."
    
    # Copy the key with the peer-hostname-key.pem naming pattern
    cp server.key "$INSTALL_DIR/runtime/etcd/certs/peer-${hostname}-key.pem"
    
    # Create the certificate with the peer-hostname.pem naming pattern
    openssl req -x509 -nodes -new -key "$INSTALL_DIR/runtime/etcd/certs/peer-${hostname}-key.pem" \
      -out "$INSTALL_DIR/runtime/etcd/certs/peer-${hostname}.pem" \
      -days 365 \
      -config cert.cnf \
      -extensions v3_req
    
    # Also create standard server/client certs for completeness
    cp server.key "$INSTALL_DIR/runtime/etcd/certs/server-key.pem"
    cp server.crt "$INSTALL_DIR/runtime/etcd/certs/server.pem"
    cp server.key "$INSTALL_DIR/runtime/etcd/certs/client-key.pem"
    cp server.crt "$INSTALL_DIR/runtime/etcd/certs/client.pem"
    
    # Set correct permissions
    chmod 644 $INSTALL_DIR/runtime/etcd/certs/*.pem 2>/dev/null || true
    chmod 600 $INSTALL_DIR/runtime/etcd/certs/*-key.pem 2>/dev/null || true
    
    log_info "SSL certificates generated, trusted, and copied to etcd certs directory with correct naming patterns."
}


# Test and fix Node.js environment
test_fix_nodejs() {
    log_info "Testing Node.js environment..."
    
    # First check if node and npm are available
    if ! command_exists node || ! command_exists npm; then
        log_info "Node.js or npm not found in path. Fixing..."
        
        # Check if nvm is installed
        if [ -d "$HOME/.nvm" ]; then
            log_info "nvm is installed. Setting up environment..."
            
            # Source nvm
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
            
            # Check if node 18 is installed through nvm
            if nvm ls | grep -q "v18"; then
                log_info "Node.js 18 is installed. Activating..."
                nvm use 18
            else
                log_info "Installing Node.js 18..."
                nvm install 18
                nvm use 18
                nvm alias default 18
            fi
        else
            log_info "nvm not found. Installing nvm and Node.js..."
            curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
            
            # Source nvm
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
            
            # Install Node.js 18
            nvm install 18
            nvm use 18
            nvm alias default 18
        fi
    fi
    
    # Check if node and npm are now available
    if command_exists node && command_exists npm; then
        log_info "Node.js $(node --version) and npm $(npm --version) are now available."
        
        # Check if pm2 is installed
        if ! command_exists pm2; then
            log_info "Installing pm2..."
            npm install -g pm2
            if ! command_exists pm2; then
                log_warn "pm2 installation with npm failed. Trying with sudo..."
                sudo npm install -g pm2
            fi
        fi
        
        if command_exists pm2; then
            log_info "pm2 is installed and available."
        else
            log_error "Failed to install pm2. Please try running 'sudo npm install -g pm2' manually."
        fi
    else
        log_error "Failed to set up Node.js environment. Please install Node.js manually."
    fi
    
    # Add nvm initialization to shell profile if not already present
    if ! grep -q 'NVM_DIR' ~/.bashrc; then
        log_info "Adding nvm initialization to ~/.bashrc..."
        echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
        echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
    fi
    
    log_info "Node.js environment setup completed."
    log_info "IMPORTANT: For changes to take effect in your profile, you may need to log out and log back in."
    log_info "Alternatively, source your profile with: source ~/.bashrc"
}

# Function to start a service
start_service() {
    local service_name=$1
    log_info "Starting $service_name..."
    
    if [ "$IS_REDHAT" = true ]; then
        sudo systemctl start $service_name
        sudo systemctl enable $service_name
    else
        sudo service $service_name start
    fi
    
    if [ $? -eq 0 ]; then
        log_info "$service_name started successfully"
    else
        log_error "Failed to start $service_name"
        return 1
    fi
}

# Function to stop a service
stop_service() {
    local service_name=$1
    log_info "Stopping $service_name..."
    
    if [ "$IS_REDHAT" = true ]; then
        sudo systemctl stop $service_name
    else
        sudo service $service_name stop
    fi
    
    if [ $? -eq 0 ]; then
        log_info "$service_name stopped successfully"
    else
        log_error "Failed to stop $service_name"
        return 1
    fi
}

# Function to restart a service
restart_service() {
    local service_name=$1
    log_info "Restarting $service_name..."
    
    if [ "$IS_REDHAT" = true ]; then
        sudo systemctl restart $service_name
    else
        sudo service $service_name restart
    fi
    
    if [ $? -eq 0 ]; then
        log_info "$service_name restarted successfully"
    else
        log_error "Failed to restart $service_name"
        return 1
    fi
}

# Function to check if a service is running
is_service_running() {
    local service_name=$1
    
    if [ "$IS_REDHAT" = true ]; then
        systemctl is-active --quiet $service_name
    else
        service $service_name status > /dev/null 2>&1
    fi
    
    return $?
}

# Function to wait for a service to be running
wait_for_service() {
    local service_name=$1
    local timeout=${2:-30}
    local interval=1
    local start_time=$(date +%s)
    
    while ! is_service_running $service_name; do
        if [ $(($(date +%s) - start_time)) -gt $timeout ]; then
            log_error "Timeout waiting for $service_name to start"
            return 1
        fi
        sleep $interval
    done
    
    log_info "$service_name is running"
    return 0
}

check_installation_directory() {
    # Check if the directory kamiwaza exists under the installation directory and has data and the correct permissions
    if [ -d "$INSTALL_DIR/kamiwaza" ]; then
        log_info "Kamiwaza installation directory exists and has data."
    else
        while true; do
            read -p "Do you want to use SSH (s) or HTTPS (h) for cloning? [s/h]: " clone_method
            if [[ "$clone_method" == "s" ]]; then
                git clone git@github.com:m9e/kamiwaza.git "$INSTALL_DIR/kamiwaza"
                break
            elif [[ "$clone_method" == "h" ]]; then
                git clone https://github.com/m9e/kamiwaza.git "$INSTALL_DIR/kamiwaza"
                break
            else
                log_error "Invalid option. Please enter 's' for SSH or 'h' for HTTPS."
            fi
        done
    fi
}

# Main function to orchestrate the installation
main() {
    log_info "Starting Kamiwaza installation on Ubuntu..."

    # Step 1: Check/Prepare Installation Directory
    log_info "########################################################"
    log_info "Step 1: Check/Prepare Installation Directory"
    log_info "########################################################"
    export INSTALL_DIR
    check_installation_directory

    # Step 2: Set Permissions for Installation Directory
    log_info "########################################################"
    log_info "Step 2: Set Permissions for Installation Directory"
    log_info "########################################################"
    sudo chmod -R 770 $INSTALL_DIR
    sudo chown -R ${current_user}:${current_user} $INSTALL_DIR

    # Step 3: Check Distribution/Environment
    log_info "########################################################"
    log_info "Step 3: Check Distribution/Environment"
    log_info "########################################################"
    check_distribution

    log_info "########################################################"
    log_info "Step 4: Install dependencies"
    log_info "########################################################"
    install_dependencies

    log_info "########################################################"
    log_info "Step 5: Verify Docker"
    log_info "########################################################"
    verify_docker

    log_info "########################################################"
    log_info "Step 6: Generate SSL certificate"
    log_info "########################################################"
    generate_ssl_cert

    log_info "########################################################"
    log_info "Step 7: Setup Python environment"
    log_info "########################################################"
    setup_python_env

    log_info "########################################################"
    log_info "Step 8: Launch Ray"
    log_info "########################################################"
    launch_ray

    log_info "########################################################"
    log_info "Step 10: Install Kamiwaza"
    log_info "########################################################"
    install_kamiwaza

    log_info "Running final permissions check and fix..."
    current_user=$(whoami)

    # Fix deployment directory permissions
    if [ -d "kamiwaza/deployment" ]; then
        sudo chown -R ${current_user}:${current_user} kamiwaza/deployment
    fi

    # Fix frontend permissions
    if [ -d "frontend" ]; then
        sudo chown -R ${current_user}:${current_user} frontend
    fi
    read -p "Do you want to install llamacpp? [y/N]: " install_llamacpp
    if [[ "$install_llamacpp" == "y" || "$install_llamacpp" == "Y" ]]; then
        log_info "### Installing llamacpp..."
        bash build-llama-cpp.sh
    fi
    
    # Set permissions on runtime directory if it exists
    if [ -d "runtime" ]; then
        sudo chown -R ${current_user}:${current_user} runtime
    fi

    log_info "Installation process completed!"
    log_info "To confirm the CockroachDB is working, navigate to:"
    log_info "cd kamiwaza/deployment/envs/default/kamiwaza-cockroachdb/amd64"

    log_info "Remember to activate the virtual environment when needed with:"
    log_info "source ./venv/bin/activate"

    log_info "If you encounter permission issues, run the troubleshooting option 8 to fix permissions."
    log_info "########################################################"
    log_info "Installation process completed!"
    log_info "########################################################"
    exit 0
}

# Troubleshooting menu
troubleshoot() {
    while true; do
        echo
        echo "==== Troubleshooting Menu ===="
        echo "1. Kill processes on port 100xx"
        echo "2. Kill Python/Jupyter/Webpack processes"
        echo "3. Reset Ray (stop and restart)"
        echo "4. Adjust permissions / Configure sudo NOPASSWD"
        echo "5. Ensure Containers are running"
        echo "6. Reset Database"
        echo "7. Generate and trust a self-signed SSL certificate"
        echo "8. Test and fix Node.js environment"
        echo "9. Install Kamiwaza core"
        echo "10. Return to main menu"
        echo "============================="
        read -p "Enter your choice: " choice
        
        case $choice in
            1) kill_port_processes ;;
            2) kill_dev_processes ;;
            3)
                log_info "Resetting Ray..."
                ray stop
                bash start-ray.sh
                ;;
            4)
                log_info "Adjusting permissions..."
                sudo bash linux-permissions.sh
                ;;
            5) bash containers-up.sh ;;
            6)
                log_info "Resetting Database..."
                source ./venv/bin/activate
                python -m util.admin_db_reset
                ;;
            7) generate_ssl_cert ;;
            8) test_fix_nodejs ;;
            9) install_kamiwaza ;;
            10) return ;;
            *) log_error "Invalid option" ;;
        esac
    done
}

# Check if this script is being called with non-interactive flag
if [ "$NON_INTERACTIVE" = true ]; then
    log_info "Running in non-interactive mode, performing full installation..."
    main
    exit 0
fi

# Menu system
while true; do
    echo
    echo "==== Kamiwaza Installation Menu ===="
    echo "1. Run full installation"
    echo "2. Verify Docker only"
    echo "3. Install dependencies only" 
    echo "4. Setup Python environment only"
    echo "5. Launch Ray only"
    echo "6. Install CUDA support only"
    echo "7. Troubleshooting options"
    echo "8. Setup Frontend only"
    echo "9. Exit"
    echo "==================================="
    read -p "Enter your choice: " choice
    
    case $choice in
        1) main ;;
        2) verify_docker ;;
        3) install_dependencies ;;
        4) setup_python_env ;;
        5) launch_ray ;;
        6) setup_cuda ;;
        7) troubleshoot ;;
        8) setup_frontend ;;
        9) 
            log_info "Exiting."
            exit 0
            ;;
        *) log_error "Invalid option" ;;
    esac
done
