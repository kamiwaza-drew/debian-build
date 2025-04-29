# Check for command line flag
FORCE_WIPE=false
if [[ "$1" == "--force-wipe" || "$1" == "-f" ]]; then
    FORCE_WIPE=true
fi

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

# Function to check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        print_in_color red "sudo is not available. This script requires sudo privileges."
        exit 1
    fi
}

# Function to get sudo password
get_sudo_password() {
    print_in_color yellow "This script requires sudo privileges to remove system files."
    print_in_color yellow "Please enter your sudo password:"
    read -s SUDO_PASSWORD
    echo

    # Test the password
    if ! echo "$SUDO_PASSWORD" | sudo -S true 2>/dev/null; then
        print_in_color red "Incorrect sudo password. Please try again."
        get_sudo_password
    else
        print_in_color green "Sudo password accepted."
    fi
}

# Function to run sudo commands with cached password
sudo_cmd() {
    echo "$SUDO_PASSWORD" | sudo -S "$@"
}

# Function to destroy dpkg and apt locks
# WARNING: Only use this if you are sure no other package process is running!
destroy_dpkg_locks() {

    sudo apt-get remove --purge kamiwaza
    sudo apt-get clean
    sudo apt-get update
    # Kill any running apt or dpkg processes
    print_in_color yellow "Killing any running apt or dpkg processes..."
    apt_pids=$(ps aux | grep -E 'apt|dpkg' | grep -v grep | awk '{print $2}')
    if [ -n "$apt_pids" ]; then
        for pid in $apt_pids; do
            print_in_color yellow "Killing process with PID: $pid"
            sudo_cmd kill -9 $pid
        done
    else
        print_in_color green "No apt or dpkg processes found running."
    fi
    
    # Clean apt cache and update package lists
    print_in_color yellow "Cleaning apt cache and updating package lists..."
    sudo_cmd apt-get clean
    sudo_cmd apt-get autoremove -y
    sudo_cmd apt-get update
    print_in_color yellow "Attempting to destroy dpkg and apt lock files..."
    sudo_cmd rm -f /var/lib/dpkg/lock
    sudo_cmd rm -f /var/lib/dpkg/lock-frontend
    sudo_cmd rm -f /var/cache/apt/archives/lock
    sudo_cmd rm -f /var/lib/apt/lists/lock
    sudo_cmd rm -f /var/lib/apt/lists/lock-frontend
    print_in_color green "All dpkg and apt lock files have been removed (if they existed)."
    sudo_cmd rm -f /usr/lib/command-not-found
    sudo_cmd rm -f /usr/share/command-not-found/command-not-found
}

# Check for sudo and get password
check_sudo
get_sudo_password

destroy_dpkg_locks

# List of components that will be removed
COMPONENTS_TO_REMOVE=(
    "Docker containers, images, and volumes"
    "Docker packages and configuration"
    "Python packages and environments"
    "CockroachDB"
    "System packages installed during Kamiwaza setup"
    "Kamiwaza installation directory (/opt/kamiwaza)"
    "Debian packages and files"
    "Pip packages and cache"
)

print_in_color blue "WARNING: This script will completely remove Kamiwaza and its dependencies from your system."
print_in_color yellow "The following components will be wiped from your system:"

for ((i=0; i<${#COMPONENTS_TO_REMOVE[@]}; i++)); do
    print_in_color red "  $((i+1)). ${COMPONENTS_TO_REMOVE[$i]}"
done

print_in_color blue "\nThis action is IRREVERSIBLE and will remove all listed components along with their data and configurations."

if [ "$FORCE_WIPE" = true ]; then
    print_in_color yellow "Proceeding with uninstallation because --force-wipe flag was provided."
else
    print_in_color yellow "\nTo proceed, please type exactly: \"Wipe my Kamiwaza install and all dependencies\""
    read -p "> " confirmation

    if [ "$confirmation" != "Wipe my Kamiwaza install and all dependencies" ]; then
        print_in_color red "Confirmation phrase does not match. Aborting uninstallation."
        exit 1
    fi
    
    print_in_color green "Confirmation received. Proceeding with uninstallation..."
fi

print_in_color blue "Starting uninstallation process..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Stop all Kamiwaza services
print_in_color blue "Stopping Kamiwaza services..."
if [ -f "stop-core.sh" ]; then
    bash stop-core.sh
fi
if [ -f "containers-down.sh" ]; then
    bash containers-down.sh
fi
if [ -f "stop-env.sh" ]; then
    bash stop-env.sh
fi
if [ -f "stop-lab.sh" ]; then
    bash stop-lab.sh
fi

# Stop and remove Docker containers, images, and volumes
if command_exists docker; then
    print_in_color blue "Cleaning up Docker..."
    docker stop $(docker ps -aq) 2>/dev/null
    docker rm $(docker ps -aq) 2>/dev/null
    docker rmi $(docker images -q) 2>/dev/null
    docker volume rm $(docker volume ls -q) 2>/dev/null
    docker system prune -af --volumes
    docker network prune -f
    
    print_in_color blue "Stopping Docker services..."
    sudo_cmd systemctl stop docker
    sudo_cmd systemctl stop docker.socket
    sudo_cmd systemctl stop containerd
    
    print_in_color blue "Purging Docker packages..."
    sudo_cmd apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
    
fi

# Kill Docker-related processes
print_in_color blue "Stopping Docker and related processes..."
pkill -9 docker
pkill -9 dockerd
pkill -9 docker-containerd
pkill -9 docker-runc
pkill -9 docker-proxy
pkill -9 docker-init

# Remove Docker packages
print_in_color blue "Removing Docker packages..."
sudo_cmd apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
sudo_cmd apt-get autoremove -y

# Remove Docker configuration
print_in_color blue "Removing Docker configuration..."
sudo_cmd rm -rf /var/lib/docker
sudo_cmd rm -rf /etc/docker
sudo_cmd rm -rf /var/run/docker.sock
sudo_cmd rm -rf /etc/default/docker
sudo_cmd rm -rf /etc/systemd/system/docker.service.d
sudo_cmd rm -rf /var/lib/containerd

# Remove Python packages and environments
print_in_color blue "Removing Python packages and environments..."
# sudo_cmd apt-get purge -y python3.10 python3.10-dev libpython3.10-dev python3.10-venv python3-pip
# sudo_cmd apt-get autoremove -y
rm -rf ~/.cache/pip
rm -rf ~/.virtualenvs
rm -rf ~/.pyenv
rm -rf ~/.python_history
rm -rf ~/.cache/*

# 5. Remove all Python binaries and libraries
# Remove Kamiwaza Python virtual environments (if any)
print_in_color blue "Removing Kamiwaza Python virtual environments..."
sudo_cmd rm -rf /opt/kamiwaza/venv
sudo_cmd rm -rf /opt/kamiwaza/.venv

# Remove user Python venvs (optional, only if you know they're safe)
rm -rf ~/.virtualenvs
rm -rf ~/.pyenv


# Remove pip packages installed for the user (optional)
USER_PACKAGES=$(pip freeze --user)
if [ -n "$USER_PACKAGES" ]; then
    echo "$USER_PACKAGES" | xargs pip uninstall -y
else
    print_in_color green "No user-installed pip packages found."
fi


# Remove Kamiwaza-related system packages (safe subset)
print_in_color blue "Removing Kamiwaza-related system packages..."
sudo_cmd apt-get purge -y golang-cfssl etcd-client net-tools jq pkg-config libcairo2-dev

# Remove Kamiwaza package itself
sudo_cmd apt-get purge -y kamiwaza
sudo_cmd dpkg --purge kamiwaza

# Remove Kamiwaza files and directories
sudo_cmd rm -rf /opt/kamiwaza ~/.kamiwaza-installed ~/.cache/kamiwaza ~/.config/kamiwaza
# sudo_cmd rm -f /usr/bin/python

# Clean up
sudo_cmd apt-get autoremove -y
sudo_cmd apt-get clean

# Remove CockroachDB
print_in_color blue "Removing CockroachDB..."
sudo_cmd rm -f /usr/local/bin/cockroach
sudo_cmd rm -rf /var/lib/cockroach
sudo_cmd rm -rf /etc/cockroach

# Remove Kamiwaza installation directory
print_in_color blue "Removing Kamiwaza installation directory..."
sudo_cmd rm -rf /opt/kamiwaza ~/.kamiwaza-installed ~/.cache/kamiwaza ~/.config/kamiwaza

# Remove deb packages and files
print_in_color blue "Removing deb packages and files..."
sudo_cmd apt-get purge -y golang-cfssl etcd-client net-tools build-essential jq pkg-config libcairo2-dev
sudo_cmd apt-get autoremove -y
rm -f *.deb
rm -f ~/kamiwaza_*.deb
sudo_cmd apt-get purge -y kamiwaza
sudo_cmd dpkg --purge kamiwaza
# Remove pip packages
print_in_color blue "Removing pip packages..."
pip freeze | xargs pip uninstall -y
sudo_cmd pip3 freeze | xargs sudo_cmd pip3 uninstall -y

# Remove packages installed during Kamiwaza setup
print_in_color blue "Removing packages installed during Kamiwaza setup..."
if [ -f "/var/log/dpkg.log" ]; then
    grep install /var/log/dpkg.log | awk '{print $4}' | sort -u | xargs -r sudo_cmd apt-get purge -y
fi

# Clean up system
print_in_color blue "Cleaning up system..."
sudo_cmd apt-get clean
sudo_cmd apt-get autoremove -y
sudo_cmd rm -rf /var/cache/apt/archives/*
sudo_cmd rm -rf /var/lib/apt/lists/*

# Remove remaining Kamiwaza files
print_in_color blue "Removing remaining Kamiwaza files..."
rm -rf ~/.kamiwaza-installed
rm -rf ~/.cache/kamiwaza
rm -rf ~/.config/kamiwaza

print_in_color green "Uninstallation complete. Please restart your system to ensure all changes take effect." 
