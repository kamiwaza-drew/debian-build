#!/bin/bash

source common.sh

# Function to print messages in colors
print_in_color() {
    case $1 in
        green)
            echo -e "\033[92m$2\033[0m"
            ;;
        red)
            echo -e "\033[91m$2\033[0m"
            ;;
        yellow)
            echo -e "\033[93m$2\033[0m"
            ;;
        blue)
            echo -e "\033[94m$2\033[0m"
            ;;
        *)
            echo "$2"
            ;;
    esac
}

promote_nvm_node() {
    # Ensure NVM_DIR is set
    if [ -z "$NVM_DIR" ]; then
        echo "NVM_DIR is not set. Please set it and try again."
        return 1
    fi

    # Split PATH into an array
    IFS=':' read -r -a path_array <<< "$PATH"

    # Find indices of the NVM_DIR and the first homebrew path
    nvm_index=-1
    homebrew_index=-1

    for i in "${!path_array[@]}"; do
        if [[ "${path_array[i]}" == *"${NVM_DIR}"* ]]; then
            nvm_index=$i
        fi
        if [[ "${path_array[i]}" == *"/opt/homebrew"* && $homebrew_index -eq -1 ]]; then
            homebrew_index=$i
        fi
    done

    # Check if we found both paths and if NVM_DIR is before the homebrew path
    if [ $nvm_index -ge 0 ] && [ $homebrew_index -ge 0 ] && [ $nvm_index -gt $homebrew_index ]; then
        # Move NVM_DIR path to 1 position before the homebrew path
        nvm_path="${path_array[nvm_index]}"
        unset 'path_array[nvm_index]'
        path_array=("${path_array[@]:0:$homebrew_index}" "$nvm_path" "${path_array[@]:$homebrew_index}")

        # Re-export the modified PATH
        export PATH=$(IFS=:; echo "${path_array[*]}")
        echo "Promoted NVM path in PATH."
    else
        echo "No changes needed to PATH."
    fi
}

# Function to add NVM config to shell profile
configure_nvm_priority() {
    local shell_profile
    if [[ "$SHELL" == */zsh ]]; then
        shell_profile="$HOME/.zshrc"
    else
        shell_profile="$HOME/.bash_profile"
    fi

    [ -f "$shell_profile" ] || touch "$shell_profile"

    # Remove any existing NVM config
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' -e '/# Kamiwaza NVM Configuration/,+8d' "$shell_profile"
    else
        sed -i.bak '/# Kamiwaza NVM Configuration/,+8d' "$shell_profile"
    fi

    # Add our NVM config at the start of the file
    local tmp_file=$(mktemp)
    cat > "$tmp_file" << 'EOF'
# Kamiwaza NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Ensure NVM bin directory is at front of PATH
if [ -d "$NVM_DIR/versions/node/$(nvm version)/bin" ]; then
    PATH="$NVM_DIR/versions/node/$(nvm version)/bin:$PATH"
fi

EOF
    cat "$shell_profile" >> "$tmp_file"
    mv "$tmp_file" "$shell_profile"
    
    # Source it immediately
    # Force PATH update for current session
    if [ -d "$NVM_DIR/versions/node/$(nvm version)/bin" ]; then
        export PATH="$NVM_DIR/versions/node/$(nvm version)/bin:$PATH"
    fi
    source "$shell_profile"
}

source common.sh

print_in_color none "Checking for venv..."
if [[ "${VIRTUAL_ENV:-}" == "" ]]; then
    print_in_color red "Warning: Not running in a virtual environment; run install.sh instead"
    exit 1
fi

if [[ -z "${KAMIWAZA_RUN_FROM_INSTALL:-}" ]]; then
    print_in_color red "Don't run directly; run install.sh instead"
    exit 1
fi

pip install --upgrade -r requirements.txt

# install pymilvus 2.4.10 without dependencies
pip install --no-deps "pymilvus==2.4.10"
pip install --no-deps "milvus-lite==2.4.10"

tmp_dir=$(mktemp -d tmp_XXXXXX)
pushd "$tmp_dir" > /dev/null

echo "pwd: `pwd`"
echo "current user: $(whoami)"
if ! [ -f '../compile.sh' ] && ! [ -f 'compile.sh' ] && ! python -c "import kamiwaza" &> /dev/null; then
    print_in_color yellow "The kamiwaza package is not installed - will install"
    popd > /dev/null
    rm -rf "$tmp_dir"
    kamiwaza_wheel=$(find . -name 'kamiwaza*.whl')
    if [[ -z "$kamiwaza_wheel" ]]; then
        print_in_color red "kamiwaza wheel file not found. Please ensure it's available and rerun this installer."
        exit 1
    else
        print_in_color blue "Installing kamiwaza package from wheel file: $kamiwaza_wheel"
        pip install "$kamiwaza_wheel"
        if [[ "$?" -ne 0 ]]; then
            print_in_color red "Failed to install kamiwaza package."
            exit 1
        else
            print_in_color green "Installed. Retesting."
        fi
        tmp_dir=$(mktemp -d tmp_XXXXXX)
        pushd "$tmp_dir" > /dev/null
        if ! python -c "import kamiwaza" &> /dev/null; then
            print_in_color red "Failed to verify the installation of kamiwaza package."
            popd > /dev/null
            rm -rf "$tmp_dir"
            exit 1
        else
            popd > /dev/null
            rm -rf "$tmp_dir"
            print_in_color green "kamiwaza package was successfully installed."
        fi
    fi
else
    popd > /dev/null
    rm -rf "$tmp_dir"
    print_in_color green "kamiwaza package is installed."
fi

# Deactivate the virtual environment - with Kamiwaza installed this should no longer be needed
# and having it alive can interfere with other installs (eg, nvm setup)
deactivate || true

print_in_color none "Checking for prerequisites..."
# Test if 'cockroach' command is available in PATH
if ! command -v cockroach &> /dev/null; then
    print_in_color red "CockroachDB command line tool 'cockroach' could not be found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install CockroachDB using Homebrew with the command: brew install cockroach"
    else
        echo "Please install CockroachDB from https://www.cockroachlabs.com/ and ensure 'cockroach' is in your PATH."
    fi
    exit 1
else
    print_in_color green "CockroachDB command line tool 'cockroach' is available."
fi

# Test if 'jq' command is available in PATH
if ! command -v jq &> /dev/null; then
    print_in_color red "jq command line tool could not be found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install jq using Homebrew with the command: brew install jq"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "On Linux, install with: sudo apt install -y jq"
    else
        echo "Please install jq from your package manager and ensure 'jq' is in your PATH."
    fi
    exit 1
else
    print_in_color green "jq command line tool is available."
fi

# Test if 'cfssl' command is available in PATH
if ! command -v cfssl &> /dev/null; then
    print_in_color red "CFSSL command line tool 'cfssl' could not be found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install CFSSL using Homebrew with the command: brew install cfssl"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "On Linux, the installer should have installed, but:"
        echo "sudo apt install -y python3.10 python3.10-dev libpython3.10-dev python3.10-venv golang-cfssl python-is-python3 etcd-client net-tools"
    else
        echo "Please install CFSSL from https://cfssl.org/ and ensure 'cfssl' is in your PATH."
    fi
    exit 1
else
    print_in_color green "CFSSL command line tool 'cfssl' is available."
fi

# Test if 'nvm' command is available and try to load it if not
if ! command -v nvm &> /dev/null; then
    if [[ "${KAMIWAZA_COMMUNITY:-}" != "true" ]]; then
        # Enterprise edition: Set up NVM in /opt/kamiwaza/nvm
        if [ ! -d "/opt/kamiwaza/nvm" ]; then
            print_in_color yellow "Setting up NVM in /opt/kamiwaza/nvm..."
            sudo mkdir -p /opt/kamiwaza/nvm
            sudo chown -R ${USER}:${USER} /opt/kamiwaza/nvm
            
            # Set up system-wide NVM config
            sudo tee /etc/profile.d/kamiwaza-nvm.sh << 'EOF'
export NVM_DIR="/opt/kamiwaza/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
            sudo chmod 644 /etc/profile.d/kamiwaza-nvm.sh
        fi
        
        # Set NVM_DIR and check if already installed
        export NVM_DIR="/opt/kamiwaza/nvm"
        if [[ ! -f "$NVM_DIR/nvm.sh" ]]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR="/opt/kamiwaza/nvm" bash
        fi
        
        # Source NVM
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    else
        # Community edition: Use standard home directory installation
        if [[ "$(uname)" == "Darwin" ]]; then
            # OSX-specific handling
            if [[ -n "${NVM_DIR:-}" && -f "${NVM_DIR}/nvm.sh" ]]; then
                print_in_color yellow "Found NVM installation in \$NVM_DIR, loading..."
                . "${NVM_DIR}/nvm.sh"
            elif [[ -f "${HOME}/.nvm/nvm.sh" ]]; then
                print_in_color yellow "Found NVM in default location, loading..."
                export NVM_DIR="$HOME/.nvm"
                . "${HOME}/.nvm/nvm.sh"
            else
                print_in_color yellow "Installing NVM..."
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            fi
        else
            # Linux community edition
            if [[ -n "${NVM_DIR:-}" && -f "${NVM_DIR}/nvm.sh" ]]; then
                print_in_color yellow "Found NVM installation in \$NVM_DIR, loading..."
                . "${NVM_DIR}/nvm.sh"
            elif [[ -f "${HOME}/.nvm/nvm.sh" ]]; then
                print_in_color yellow "Found NVM in default location, loading..."
                export NVM_DIR="$HOME/.nvm"
                . "${HOME}/.nvm/nvm.sh"
            else
                print_in_color yellow "Installing NVM..."
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            fi
        fi
    fi
   
    # Check if loading worked
    if ! command -v nvm &> /dev/null; then
        print_in_color red "Failed to load or install NVM"
        exit 1
    fi
fi

print_in_color green "Node Version Manager (nvm) is available."

# Handle Node installation and version checking
if [[ "$(uname)" == "Darwin" ]]; then
    # OSX-specific Node version handling
    attempt=1
    max_attempts=3
    
    while [ $attempt -le $max_attempts ]; do
        if ! command -v node &> /dev/null; then
            print_in_color yellow "Node not found. Installing Node 22..."
            nvm install 22
            nvm alias default 22
            nvm use 22
        else
            node_version=$(node --version || echo "")
            if [[ ! "$node_version" =~ ^v22 ]]; then
                print_in_color yellow "Node version $node_version detected. Switching to Node 22..."
                nvm install 22
                nvm alias default 22
                nvm use 22
                
                # Check if version switched successfully
                node_version=$(node --version || echo "")
                if [[ ! "$node_version" =~ ^v22 ]]; then
                    if [ $attempt -eq 1 ]; then
                        print_in_color yellow "Failed to switch to Node 22. Attempting to adjust PATH..."
                        promote_nvm_node
                        hash -r
                    elif [ $attempt -eq $max_attempts ]; then
                        print_in_color red "ERROR: Unable to set Node version to 22 after multiple attempts."
                        print_in_color red "This might be caused by:"
                        print_in_color red "1. Homebrew's node installation taking precedence"
                        print_in_color red "2. A system-wide Node installation"
                        print_in_color red "3. PATH conflicts in your shell configuration"
                        print_in_color red "\nTroubleshooting steps:"
                        current_node=$(which node)
                        print_in_color red "1. Current node path is: $current_node"
                        print_in_color red "2. Check your PATH variable for conflicting Node installations"
                        print_in_color red "3. Consider running: brew uninstall node"
                        exit 1
                    fi
                else
                    print_in_color green "Successfully switched to Node 22"
                    break
                fi
            else
                print_in_color green "Node version $node_version detected."
                break
            fi
        fi
        
        attempt=$((attempt + 1))
    done
else
    # Non-OSX Node version handling
    if ! command -v node &> /dev/null; then
        print_in_color yellow "Node not found. Installing Node 22..."
        nvm install 22
        nvm alias default 22
        nvm use 22
    else
        node_version=$(node --version || echo "")
        if [[ ! "$node_version" =~ ^v22 ]]; then
            print_in_color yellow "Node version $node_version detected. Switching to Node 22..."
            nvm install 22
            nvm alias default 22
            nvm use 22
        else
            print_in_color green "Node version $node_version detected."
        fi
    fi
fi

# Test if 'etcd-client' command is available in PATH
if ! command -v etcdctl &> /dev/null; then
    print_in_color red "etcd-client command line tool 'etcdctl' could not be found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install etcd-client using Homebrew with the command: brew install etcd"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "On Linux, the installer should have installed, but:"
        echo "sudo apt install -y etcd-client"
    else
        echo "Please install etcd-client from https://etcd.io/ and ensure 'etcdctl' is in your PATH."
    fi
    exit 1
else
    etcdctl_version=$(etcdctl version 2>/dev/null | awk '/etcdctl version:/ {print $3}')
    if [[ -z "$etcdctl_version" ]]; then
        print_in_color yellow "Unable to determine etcdctl version. Assuming it needs an update."
        etcdctl_version="0.0.0"  # Set to a version that will trigger the update
    fi
    
    if [[ "$etcdctl_version" < "3.5" ]]; then
        print_in_color yellow "etcd-client version is less than 3.5 or unknown. Attempting to update..."
        if [[ "$(uname)" == "Darwin" ]]; then
            print_in_color yellow 'Run `brew upgrade etcd` to update etcd on macOS.'
            exit 1
        else
            print_in_color yellow 'Running install-or-update-etcd.sh...'
            source install-or-update-etcd.sh
            # Re-test etcdctl version after update
            if ! command -v etcdctl &> /dev/null; then
                print_in_color red "Failed to install etcdctl. Please install manually."
                exit 1
            fi
            etcdctl_version=$(etcdctl version 2>/dev/null | awk '/etcdctl version:/ {print $3}')
            if [[ -z "$etcdctl_version" ]] || [[ "$etcdctl_version" < "3.5" ]]; then
                print_in_color red "Failed to update etcd-client to version 3.5 or higher, or unable to determine version. Please update manually."
                exit 1
            fi
        fi
    fi
    
    if [[ -z "$etcdctl_version" ]]; then
        print_in_color yellow "etcd-client command line tool 'etcdctl' is available, but unable to determine its version."
    else
        print_in_color green "etcd-client command line tool 'etcdctl' is available and version is $etcdctl_version."
    fi
fi

# Test if 'netstat' command is available in PATH
if ! command -v netstat &> /dev/null; then
    print_in_color red "netstat command line tool 'netstat' could not be found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install netstat using Homebrew with the command: brew install net-tools"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "On Linux, the installer should have installed, but:"
        echo "sudo apt install -y net-tools"
    else
        echo "Please install netstat from your package manager and ensure 'netstat' is in your PATH."
    fi
    echo "netstat is optional, so proceeding"
else
    print_in_color green "netstat command line tool 'netstat' is available."
fi

# Test if 'openssl' command is available
if ! command -v openssl &> /dev/null; then
    print_in_color red "openssl command line tool 'openssl' could not be found."
    print_in_color red "### YOU CAN SET JUPYTERHUB_CRYPT_KEY=[secure 32 character hex string] instead, or install - this install will proceed"
    read -p "Press Enter to continue"
else
    print_in_color green "openssl command line tool 'openssl' is available."
fi

# Test for Python 3.10 availability (either as python3.10 or python)
if python3.10 --version &> /dev/null; then
    python_version=$(python3.10 --version)
    print_in_color green "Python 3.10 is available: $python_version"
elif python --version &> /dev/null && [[ $(python --version) == "Python 3.10."* ]]; then
    python_version=$(python --version)
    print_in_color green "Python 3.10 is available: $python_version"
else
    print_in_color red "Python 3.10 is required but not found."
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "If you are on OSX, you can install Python 3.10 using Homebrew with the command: brew install python@3.10"
    elif [[ "$(uname)" == "Linux" ]]; then
        echo "On Linux, the installer should have installed, but:"
        echo "sudo apt install -y python3.10 python3.10-dev libpython3.10-dev python3.10-venv"
    else
        echo "Please install Python 3.10 from https://www.python.org/ and ensure it's in your PATH."
    fi
    exit 1
fi

print_in_color none "Checking for Docker installation and permissions..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_in_color red "Docker could not be found. Please install Docker and try again."
    exit 1
else
    print_in_color green "Docker is installed."
fi

# Check if 'docker compose' command is available
if ! docker compose version &> /dev/null; then
    print_in_color red "'docker compose' command is not available. Please ensure you have Docker Compose v2 and try again."
    exit 1
else
    print_in_color green "'docker compose' command is available."
fi

# Test if the user has access to the Docker daemon
if ! docker info &> /dev/null; then
    print_in_color red "You do not have access to the Docker daemon. Please ensure your user is added to the 'docker' group and try again."
    exit 1
else
    print_in_color green "You have access to the Docker daemon."
fi

print_in_color green "***********************************************************"
print_in_color green "==== Kamiwaza Installer ===="
print_in_color yellow "Your use of this software is subject to the license agreement. If you do not agree to the license terms, say no, exit this installer, and delete all copies of the software"

if [[ "${USER_ACCEPTED_KAMIWAZA_LICENSE:-}" == "yes" ]]; then
    print_in_color green "License agreement accepted via CLI flag. Continuing with installation..."
else
    if [ ! -f LICENSE-kamiwaza ] ; then
        print_in_color red "License file not found. Contact support@kamiwaza.ai"
        exit 1
    fi
    bash read_eula.sh
    if [ $? -ne 0 ]; then
        print_in_color red "You did not agree to the license terms. Exiting installer."
        exit 1
    else
        print_in_color green "You have agreed to the license terms. Continuing with installation..."
    fi
fi
# Check if 'notebook-venv' directory does not exist
if [ ! -d 'notebook-venv' ] ; then
    print_in_color none "Creating and activating the notebook virtual environment..."
    # Proceed with creating and activating the notebook virtual environment
    (
    python -m venv notebook-venv
    print_in_color none " ### Installing Notebook environment and packages... "
    source notebook-venv/bin/activate
    kamiwaza_wheel=$(find . -name 'kamiwaza*.whl')
    
    if [[ -z "$kamiwaza_wheel" ]]; then
        if [ -f "compile.sh" ]; then
            print_in_color yellow "Skipping kamiwaza-wheel install for development install."
        else
            print_in_color red "Warning: kamiwaza wheel file not found. Please ensure the wheel file is available and rerun this installer."
        fi
    else
        pip install "$kamiwaza_wheel"
    fi
    
    pip install -r requirements.txt
    pip install -r notebooks/extra-requirements.txt
    # install pymilvus 2.4.10 without dependencies
    pip install --no-deps "pymilvus==2.4.10"
    pip install --no-deps "milvus-lite==2.4.10"
    )
else
    print_in_color red "Warning: 'notebook-venv' already exists. This may indicate that Kamiwaza is already installed."
    read -p "Do you want us to attempt to install the virtual environment and requirements anyway? (yes/no) " attempt_install
    if [[ "$attempt_install" != "yes" && "$attempt_install" != "y" ]]; then
        print_in_color yellow "Skipping virtual environment and requirements installation."
    else
        # Proceed with creating and activating the notebook virtual environment
        (
        python -m venv notebook-venv
        print_in_color green " ### Installing Notebook environment and packages... "
        source notebook-venv/bin/activate
        kamiwaza_wheel=$(find . -name 'kamiwaza*.whl')
        
        if [[ -z "$kamiwaza_wheel" ]]; then
            if [ -f "compile.sh" ]; then
                print_in_color yellow "Skipping kamiwaza-wheel install for development install."
            else
                print_in_color red "Warning: kamiwaza wheel file not found. Please ensure the wheel file is available and rerun this installer."
            fi
        else
            pip install "$kamiwaza_wheel"
        fi
        
        pip install -r requirements.txt
        pip install -r notebooks/extra-requirements.txt
        )
    fi
fi

# deactivate notebook venv if needed
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    deactivate || true
fi

source venv/bin/activate

if [[ "$(uname)" != "Darwin" ]]; then
    print_in_color none "Checking for /opt/kamiwaza directory..."
    if mountpoint -q "/opt/kamiwaza"; then
        print_in_color green "/opt/kamiwaza is a mount point. Configuring Docker to use it."
        setup_docker_root "/opt/kamiwaza/containers"
    else
        print_in_color yellow "/opt/kamiwaza directory not found. Skipping Docker root configuration."
    fi
fi

# Verify environment and cluster configuration
verify_cluster_config() {
    if [[ -f "/etc/kamiwaza/config/is_worker" ]]; then
        if [[ -z "${KAMIWAZA_HEAD_IP:-}" ]]; then
            print_in_color red "Worker node detected but KAMIWAZA_HEAD_IP not set"
            exit 1
        fi
    fi
}

verify_cluster_config

# Check for --install_llamacpp flag and set variable
install_llamacpp="no"
for arg in "$@"; do
    if [ "$arg" == "--install_llamacpp" ]; then
        install_llamacpp="yes"
        break
    fi
done

if [ -d "frontend" ] ; then
    print_in_color none "### Installing frontend..."
    cd ${KAMIWAZA_ROOT:-.}/frontend && rm -rf package-lock.json && rm -rf node_modules && npm install && npm run postinstall && npm run --loglevel=error build
    result=$?
    cd -
    if [ $result -eq 0 ] ; then
        print_in_color green "Installed successfully."
    else
        print_in_color red "### WARNING: Frontend install/build failed"
        print_in_color red "### Aborting install "
        exit 1
    fi
fi

if [ -f llamacpp.commit ] ; then
    if [[ "$install_llamacpp" == "yes" || "$(uname)" == "Darwin" ]]; then
        print_in_color green "### Installing llamacpp..."
        bash build-llama-cpp.sh
    else
        print_in_color yellow "Skipping llamacpp installation."
    fi
fi

print_in_color none "### Running Kamiwaza install.py..."
python install.py
if [ $? -ne 0 ]; then
    print_in_color red "Kamiwaza install.py failed. Exiting."
    exit 1
else
    print_in_color green "Kamiwaza install.py completed successfully."
    print_in_color green "### Kamiwaza is installed. ###"
    print_in_color green "### Startup with: bash startup/kamiwazad.sh start ###"
    touch ~/.kamiwaza-installed
fi
