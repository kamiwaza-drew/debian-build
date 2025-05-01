#!/bin/bash

# Script to fix Docker permissions issue by adding the current user to the docker group
# and configure sudo NOPASSWD for the current user
# Can be run with or without sudo privileges

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

# Get the current username
CURRENT_USER=$(whoami)

# Function to fix user-level permissions (no sudo required)
fix_user_permissions() {
    local user=$1
    log_info "Fixing user-level permissions for: $user"

    # Fix Ray permissions
    log_info "Setting up Ray directories and permissions..."
    mkdir -p ~/.ray
    chmod 700 ~/.ray

    # If /tmp/ray exists and we can access it
    if [ -d "/tmp/ray" ]; then
        log_info "Fixing /tmp/ray permissions..."
        # Try to clean up any stale session directories
        rm -rf /tmp/ray/session_* 2>/dev/null || true
        chmod -R 777 /tmp/ray 2>/dev/null || log_warn "Could not set all permissions on /tmp/ray - you may need to run with sudo"
    fi

    # Create Docker config directory
    log_info "Setting up Docker config directory..."
    mkdir -p ~/.docker
    chmod 700 ~/.docker

    # If we're in the Kamiwaza directory
    if [ -d "/opt/kamiwaza" ]; then
        log_info "Setting Kamiwaza directory permissions..."
        
        # Try to fix permissions on key directories
        for dir in runtime frontend kamiwaza venv; do
            if [ -d "/opt/kamiwaza/$dir" ]; then
                chmod -R u+rw "/opt/kamiwaza/$dir" 2>/dev/null || log_warn "Could not set all permissions on /opt/kamiwaza/$dir"
            fi
        done
    fi

    # Create .datahub directory
    log_info "Setting up DataHub directory..."
    mkdir -p ~/.datahub
    chmod 700 ~/.datahub
}

# Function to fix system-level permissions (requires sudo)
fix_system_permissions() {
    local real_user=$1
    log_info "Fixing system-level permissions for user: $real_user"

    # Get the real user (the one who ran sudo)
    if [ -z "$real_user" ]; then
        log_info "Running as root. Please specify the username to configure:"
        read real_user
        
        # Verify user exists
        if ! id "$real_user" &>/dev/null; then
            log_error "User $real_user does not exist."
            exit 1
        fi
    fi

    log_info "Configuring sudo NOPASSWD for user: $real_user"

    # Create a sudoers file for the user
    SUDOERS_FILE="/etc/sudoers.d/$real_user"

    # Check if file already exists
    if [ -f "$SUDOERS_FILE" ]; then
        log_warn "A sudoers file for $real_user already exists."
        log_info "Do you want to overwrite it? (y/n)"
        read ANSWER
        if [ "$ANSWER" != "y" ]; then
            log_info "Operation cancelled."
            return
        fi
    fi

    # Create the sudoers file with proper permissions
    echo "$real_user ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"

    # Verify syntax with visudo
    if visudo -c -f "$SUDOERS_FILE"; then
        log_info "Successfully configured sudo NOPASSWD for user $real_user"
    else
        log_error "The sudoers file has syntax errors."
        log_info "Removing the file to prevent lockout."
        rm "$SUDOERS_FILE"
        return 1
    fi

    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        return 1
    fi

    # Check if the docker group exists
    if ! getent group docker &> /dev/null; then
        log_info "Docker group does not exist. Creating it..."
        groupadd docker
    fi

    # Add the user to the docker group
    log_info "Adding $real_user to the docker group..."
    usermod -aG docker $real_user

    # Set permissions on the Docker socket
    log_info "Setting permissions on the Docker socket..."
    chmod 666 /var/run/docker.sock

    # Set permissions on Ray directories
    log_info "Setting permissions on Ray directories..."
    mkdir -p /tmp/ray
    # Remove and recreate any existing session directories to ensure clean permissions
    rm -rf /tmp/ray/session_* || true
    # Set ownership and permissions recursively
    chown -R $real_user:$real_user /tmp/ray
    chmod -R 777 /tmp/ray
    # Ensure the directory itself is sticky to prevent deletion by others
    chmod +t /tmp/ray
    
    # Create placeholder session directory to ensure permissions are inherited
    mkdir -p /tmp/ray/session_placeholder
    chown -R $real_user:$real_user /tmp/ray/session_placeholder
    chmod -R 777 /tmp/ray/session_placeholder

    # Make the kamiwaza-deploy directory fully writable by the current user
    if [ -d "$SCRIPT_DIR" ]; then
        log_info "Setting permissions on the kamiwaza-deploy directory..."
        chown -R $real_user:$real_user $SCRIPT_DIR
        chmod -R 777 $SCRIPT_DIR
    fi

    # Set up Docker to start on boot
    log_info "Setting up Docker to start on boot..."
    systemctl enable docker
}

# Main execution
if [ "$EUID" -eq 0 ]; then
    # Running with sudo
    REAL_USER=$SUDO_USER
    fix_system_permissions "$REAL_USER"
    log_info "System-level permissions fixed. Now fixing user-level permissions..."
    # Run user-level fixes as the real user
    su - "$REAL_USER" -c "$(declare -f fix_user_permissions); fix_user_permissions '$REAL_USER'"
else
    # Running without sudo
    log_warn "Running without sudo - only user-level permissions will be fixed"
    log_warn "For full permission fixes, run with: sudo $0"
    fix_user_permissions "$CURRENT_USER"
fi

log_info "================================================================="
log_info "Permission fixes completed!"
log_info "If you still have permission issues, you may need to:"
log_info "1. Run this script with sudo for full system-level fixes"
log_info "2. Log out and log back in"
log_info "3. Run: newgrp docker"
log_info "================================================================="