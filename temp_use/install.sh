#!/bin/bash

# RUN DIRECTLY
# bash /opt/kamiwaza/install.sh --community --i-accept-the-kamiwaza-license
# to copy to the opt directory
# sudo cp temp_use/install.sh /opt/kamiwaza/install.sh

# TODO - harden things like etcd version check
#set -euo pipefail
# If WSL2, run wsl-install.sh
echo "DREW 333 INSTALL SH"
cd /opt/kamiwaza
echo "Working directory: $(pwd)"
echo "Current user: $(whoami)"

if [[ "$(uname)" == "Linux" ]]; then
        if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
            echo "LINUX: Running WSL. linux-install.sh"
            bash linux-install.sh --non-interactive
        else
            echo "LINUX: Not running on WSL2. Running linux-install.sh"
            bash linux-install.sh --non-interactive
        fi
else
    echo "Not running on Linux" 
fi
# unset KAMIWAZA_ROOT in case of weird reinstall cases
unset KAMIWAZA_ROOT

# Initialize variables for tracking installation progress
START_TIME=$(date +%s)
TOTAL_STEPS=10  # Total number of major installation steps
CURRENT_STEP=0


# Function to update and display progress
update_progress() {
    local step_name="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - START_TIME))
    local elapsed_minutes=$((elapsed_time / 60))
    local elapsed_seconds=$((elapsed_time % 60))
    
    echo "┌────────────────────────────────────────────────────────────┐"
    echo "│ Progress: [$percentage%] Step $CURRENT_STEP/$TOTAL_STEPS: $step_name"
    echo "│ Time elapsed: ${elapsed_minutes}m ${elapsed_seconds}s"
    echo "└────────────────────────────────────────────────────────────┘"
}

source set-kamiwaza-root.sh

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

# don't permit unless flag passed
unset USER_ACCEPTED_KAMIWAZA_LICENSE

update_progress "Initializing installation"

# Check for community install file
if [[ -f ".kamiwaza_install_community" ]]; then
    export KAMIWAZA_COMMUNITY=true
    export KAMIWAZA_SWARM_HEAD=true
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --community)
            # Community edition uses local env.sh and acts as head node
            export KAMIWAZA_COMMUNITY=true
            export KAMIWAZA_SWARM_HEAD=true
            shift
            ;;
        --head)
            export KAMIWAZA_SWARM_HEAD=true
            shift
            ;;
        --worker)
            if [[ -z "${KAMIWAZA_HEAD_IP:-}" ]]; then
                print_in_color red "KAMIWAZA_HEAD_IP must be set for worker nodes"
                exit 1
            fi
            shift
            ;;
        --i-accept-the-kamiwaza-license)
            export USER_ACCEPTED_KAMIWAZA_LICENSE='yes'
            shift
            ;;
        *)
            print_in_color red "Unknown option: $1"
            echo "Usage: $0 (--head | --worker | --community) [--i-accept-the-kamiwaza-license]"
            exit 1
            ;;
    esac
done

if [[ "${KAMIWAZA_SWARM_HEAD:-}" != "true" && -z "${KAMIWAZA_HEAD_IP:-}" ]]; then
    print_in_color red "Must specify either --community, --head or --worker with KAMIWAZA_HEAD_IP set"
    exit 1
fi

if [[ -n "${KAMIWAZA_HEAD_IP:-}" ]]; then
    export KAMIWAZA_HEAD_IP  # Export it so child processes get it
fi

# Function to install OSX dependencies
install_osx_dependencies() {
    update_progress "Installing OSX dependencies"
    
    # Function to check if a command exists
    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }

    # Function to check if a brew package is installed
    brew_package_installed() {
        brew list "$1" >/dev/null 2>&1
    }

    # Function to handle errors
    handle_error() {
        print_in_color red "ERROR: $1"
        print_in_color red "Installation failed. Please check the error message above and try again."
        exit 1
    }

    # Install Homebrew if not present
    if ! command_exists brew; then
        echo "Installing Homebrew..."
        if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            handle_error "Failed to install Homebrew. Please check your internet connection and try again."
        fi
        
        # Add Homebrew to path if not already present
        if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' /Users/$USER/.zprofile; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$USER/.zprofile
        fi

        if ! grep -q 'eval "$(/opt/homebrew/bin/brew shellenv)"' /Users/$USER/.bash_profile; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$USER/.bash_profile
        fi

        eval "$(/opt/homebrew/bin/brew shellenv)" || handle_error "Failed to initialize Homebrew environment"
    else
        echo "Homebrew already installed"
    fi

    update_progress "Installing brew packages"
    
    # Install brew packages if not present
    BREW_PACKAGES="pyenv pyenv-virtualenv cairo gobject-introspection cockroachdb/tap/cockroach cfssl etcd cmake"
    for package in $BREW_PACKAGES; do
        if ! brew_package_installed $package; then
            echo "Installing $package..."
            if ! brew install $package; then
                handle_error "Failed to install $package. Try running 'brew doctor' to diagnose issues."
            fi
        else
            echo "$package already installed"
        fi
    done


    update_progress "Setting up Docker"
    
    # Install Docker.app if not present
    if ! [ -d "/Applications/Docker.app" ]; then
        echo "Installing Docker.app..."
        if ! brew install --cask docker; then
            handle_error "Failed to install Docker.app. Check if Homebrew cask is working properly."
        fi
    else
        echo "Docker.app already installed"
    fi

    # Configure Docker permissions
    sudo chown -R $(whoami):staff ~/.docker 2>/dev/null || true

    if ! brew_package_installed docker-compose; then
        echo "Installing docker-compose..."
        if ! brew install docker-compose; then
            handle_error "Failed to install docker-compose"
        fi
    else
        echo "docker-compose already installed"
    fi

    mkdir -p ~/.docker
    touch ~/.docker/config.json

    # Check if config.json already has the cli-plugins configuration
    if ! grep -q "cliPluginsExtraDirs" ~/.docker/config.json; then
        # Create temporary file with new config
        echo '{
    "cliPluginsExtraDirs": [
        "/opt/homebrew/lib/docker/cli-plugins"
    ]
    }' > ~/.docker/config.json.tmp

        # If config.json is empty, just move the temp file
        if [ ! -s ~/.docker/config.json ]; then
            mv ~/.docker/config.json.tmp ~/.docker/config.json
        else
            # Merge existing config with new config
            if ! jq -s '.[0] * .[1]' ~/.docker/config.json ~/.docker/config.json.tmp > ~/.docker/config.json.merged; then
                handle_error "Failed to update Docker configuration. Please check if jq is installed."
            fi
            mv ~/.docker/config.json.merged ~/.docker/config.json
            rm ~/.docker/config.json.tmp
        fi
    fi

    # Start Docker if not running
    if ! pgrep -x "Docker" > /dev/null; then
        echo "Starting Docker..."
        open -a Docker.app
        print_in_color yellow "Please complete the Docker Desktop installation by following any prompts that appear."
        print_in_color yellow "Once Docker Desktop is fully installed and running, press Enter to continue..."
        read -r
    fi

    update_progress "Configuring Python environment"
    
    # Configure pyenv if not already set up
    if ! grep -q 'export PATH="$HOME/.pyenv/bin:$PATH"' ~/.zshrc; then
        echo "Configuring pyenv in ~/.zshrc..."
        echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ~/.zshrc || handle_error "Failed to update ~/.zshrc"
        echo 'eval "$(pyenv init -)"' >> ~/.zshrc || handle_error "Failed to update ~/.zshrc"
        echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.zshrc || handle_error "Failed to update ~/.zshrc"
    fi

    if ! grep -q 'export PATH="$HOME/.pyenv/bin:$PATH"' ~/.bashrc; then
        echo "Configuring pyenv in ~/.bashrc..."
        echo 'export PATH="$HOME/.pyenv/bin:$PATH"' >> ~/.bashrc || handle_error "Failed to update ~/.bashrc"
        echo 'eval "$(pyenv init -)"' >> ~/.bashrc || handle_error "Failed to update ~/.bashrc"
        echo 'eval "$(pyenv virtualenv-init -)"' >> ~/.bashrc || handle_error "Failed to update ~/.bashrc"
    fi

    # Load pyenv
    if ! eval "$(pyenv init -)"; then
        handle_error "Failed to initialize pyenv. Please check your pyenv installation."
    fi
    
    if ! eval "$(pyenv virtualenv-init -)"; then
        handle_error "Failed to initialize pyenv-virtualenv. Please check your pyenv-virtualenv installation."
    fi

    # Install Python 3.10 if not present
    if ! pyenv versions | grep -q "3.10"; then
        echo "Installing Python 3.10..."
        if ! pyenv install 3.10; then
            handle_error "Failed to install Python 3.10. Check if required dependencies are installed."
        fi
    else
        echo "Python 3.10 already installed"
    fi

    # Set local Python version if not set
    if ! [ -f ".python-version" ] || ! grep -q "3.10" .python-version; then
        echo "Setting local Python version to 3.10..."
        if ! pyenv local 3.10; then
            handle_error "Failed to set local Python version to 3.10"
        fi
    fi

    update_progress "Setting up Node.js environment"
    
    # Install nvm if not present
    if ! [ -d "$HOME/.nvm" ]; then
        echo "Installing nvm..."
        if ! curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; then
            handle_error "Failed to install nvm. Please check your internet connection and try again."
        fi
        
        # Set up NVM environment
        export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" || handle_error "Failed to source nvm.sh"
    else
        echo "nvm already installed"
    fi

    # Source nvm
    export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        if ! \. "$NVM_DIR/nvm.sh"; then
            handle_error "Failed to source nvm.sh"
        fi
    else
        handle_error "nvm.sh not found. NVM installation may be corrupted."
    fi

    # Install Node.js 21 if not present
    if ! command_exists node || ! node -v | grep -q "v21"; then
        echo "Installing Node.js 21..."
        if ! nvm install 21; then
            handle_error "Failed to install Node.js 21. Please check your internet connection and try again."
        fi
    else
        echo "Node.js 21 already installed"
    fi

    # Verify all required tools are available
    REQUIRED_TOOLS=("brew" "python3.10" "pyenv" "node" "docker" "docker-compose" "etcd" "cockroach" "cfssl")
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command_exists $tool; then
            handle_error "Required tool '$tool' is not available after installation. Please check the installation logs."
        fi
    done

    echo "Installation of dependencies complete!"
}

# Call install_osx_dependencies if on OSX
if [[ "$(uname)" == "Darwin" ]]; then
    print_in_color blue "Installing OSX dependencies..."
    install_osx_dependencies
fi

update_progress "Setting up environment"

#Proceed with the rest of the installation
source common.sh
setup_environment

# Verify initialization worked - updated to check correct location based on installation type
if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
    if [[ ! -f "${KAMIWAZA_ROOT:-}/env.sh" ]]; then
        print_in_color red "Community/OSX cluster initialization failed"
        exit 1
    fi
else
    if [[ ! -f /etc/kamiwaza/env.sh && ! -f "${KAMIWAZA_ROOT:-}/env.sh" ]]; then
        print_in_color red "Enterprise cluster initialization failed"
        exit 1
    fi
fi

update_progress "Loading environment configuration"

# Source the appropriate env file
if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
    source "${KAMIWAZA_ROOT:-}/env.sh"
else
    if [[ -f /etc/kamiwaza/env.sh ]]; then
        source /etc/kamiwaza/env.sh
    elif [[ -f "${KAMIWAZA_ROOT:-}/env.sh" ]]; then
        source "${KAMIWAZA_ROOT:-}/env.sh"
    fi
fi

update_progress "Setting up virtual environment"

# Rest of venv setup and installation...
print_in_color none "Checking for virtual environment..."
if [[ -z "${VIRTUAL_ENV:-}" ]]; then
    print_in_color yellow "No virtual environment is active; creating if needed, and activating..."
    python3.10 -m venv venv
    source venv/bin/activate
    if [[ -z "${VIRTUAL_ENV:-}" ]]; then
        print_in_color red "Failed to create or activate virtual environment."
        exit 1
    fi
fi

# fix permissions if needed
chmod 774 ${KAMIWAZA_ROOT}/startup/kamiwazad.sh || true

update_progress "Running second phase installer"

print_in_color green "Running 2nd phase installer in venv..."
export KAMIWAZA_RUN_FROM_INSTALL='yes'
# Export progress tracking variables for setup.sh
export START_TIME
export CURRENT_STEP
source setup.sh
unset KAMIWAZA_RUN_FROM_INSTALL
unset USER_ACCEPTED_KAMIWAZA_LICENSE

# Display final installation status
FINAL_TIME=$(date +%s)
TOTAL_ELAPSED_TIME=$((FINAL_TIME - START_TIME))
TOTAL_MINUTES=$((TOTAL_ELAPSED_TIME / 60))
TOTAL_SECONDS=$((TOTAL_ELAPSED_TIME % 60))

echo "┌────────────────────────────────────────────────────────────┐"
echo "│ Installation Complete!                                      │"
echo "│ Total time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s                                    │"
echo "└────────────────────────────────────────────────────────────┘"
