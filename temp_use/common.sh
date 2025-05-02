get_user_group() {
    case "$(uname)" in
        "Darwin")
            echo "staff"
            ;;
        *)
            echo "${USER}"
            ;;
    esac
}

# Source set-kamiwaza-root.sh if it exists in the script's directory
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/set-kamiwaza-root.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/set-kamiwaza-root.sh"
else
    echo "Warning: set-kamiwaza-root.sh not found"
    exit 1
fi

if [ -f "${KAMIWAZA_ROOT}/.kamiwaza_install_community" ]; then
    export KAMIWAZA_COMMUNITY=true
fi

# common.sh
verify_environment() {
    # Fail fast if neither head nor worker configuration is present
    if [[ "${KAMIWAZA_SWARM_HEAD:-}" != "true" && -z "${KAMIWAZA_HEAD_IP:-}" ]]; then
        echo "Error: Must specify either KAMIWAZA_SWARM_HEAD=true or KAMIWAZA_HEAD_IP"
        exit 1
    fi

    # For worker nodes, HEAD_IP is required
    if [[ "${KAMIWAZA_SWARM_HEAD:-}" != "true" && -z "${KAMIWAZA_HEAD_IP:-}" ]]; then
        echo "Error: Worker nodes require KAMIWAZA_HEAD_IP to be set"
        exit 1
    fi
}

setup_environment() {
    # Try sourcing env.sh based on installation type
    if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
        if [[ -f "${KAMIWAZA_ROOT}/env.sh" ]]; then
            source "${KAMIWAZA_ROOT}/env.sh"
        fi
    else
        if [[ -f /etc/kamiwaza/env.sh ]]; then
            source "/etc/kamiwaza/env.sh"
        elif [[ -f "${KAMIWAZA_ROOT}/env.sh" ]]; then
            source "${KAMIWAZA_ROOT}/env.sh"
        fi
    fi

    verify_environment

    # Set up environment if not already configured
    if [[ "${KAMIWAZA_SWARM_HEAD:-}" == "true" ]]; then
        setup_head_env
    elif [[ -n "${KAMIWAZA_HEAD_IP:-}" ]]; then
        setup_worker_env
    fi
}

# In common.sh
set_env_value() {
    local key="$1"
    local value="$2"
    local env_file=""
    
    # Determine env file location based on installation type and OS
    if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
        env_file="${KAMIWAZA_ROOT}/env.sh"
    else
        env_file="/etc/kamiwaza/env.sh"
    fi

    # Ensure file exists with correct permissions
    if [[ ! -f "$env_file" ]]; then
        if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
            # For OSX/community, create in KAMIWAZA_ROOT without sudo
            touch "$env_file"
            chmod 640 "$env_file"
        else
            sudo touch "$env_file"
            sudo chown ${USER}:$(get_user_group) "$env_file"
            sudo chmod 640 "$env_file"
        fi
        
        # Add installation type marker
        if [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
            echo "# Kamiwaza Community Edition Environment" > "$env_file"
        else
            echo "# Kamiwaza Enterprise Edition Environment" | sudo tee "$env_file" >/dev/null
        fi
    fi

    if grep -q "^export ${key}=" "$env_file"; then
        # Update existing value
        if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
            sed -i.bak "s|^export ${key}=.*|export ${key}=${value}|" "$env_file" && rm -f "$env_file.bak"
        else
            sudo sed -i "s|^export ${key}=.*|export ${key}=${value}|" "$env_file"
        fi
    else
        # Add new value
        if [[ "$(uname)" == "Darwin" ]] || [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
            echo "export ${key}=${value}" >> "$env_file"
        else
            echo "export ${key}=${value}" | sudo tee -a "$env_file" >/dev/null
        fi
    fi
}

# A more robust way to pick a host ip
best_ip_for_hostname() {
    # Function to find the best IP address for hostname
    local loopback_ip="127.0.0.1"
    
    # For OSX and WSL2, handle differently
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]]; then
            echo "$loopback_ip"
            return 0
        else
            local mac_ip=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}')
            if [[ -n "$mac_ip" ]]; then
                echo "$mac_ip"
                return 0
            fi
        fi
    elif [[ "$(uname)" == "Linux" ]]; then
        if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
            echo "$loopback_ip"
            return 0
        fi
    fi
    
    # For Linux:
    
    # 1. Get all IPv4 addresses from hostname -I
    local all_hostname_ips=$(hostname -I)
    
    # 2. Filter to only IPv4 addresses
    local ipv4_ips=""
    for ip in $all_hostname_ips; do
        if [[ ! "$ip" =~ ":" ]]; then
            ipv4_ips="$ipv4_ips $ip"
        fi
    done
    ipv4_ips="${ipv4_ips## }" # Remove leading space
    
    # 3. Try to get IP from the default route interface (most reliable)
    if command -v ip &>/dev/null; then
        # Get the source IP used for internet connectivity
        local default_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        if [[ -n "$default_ip" ]]; then
            for ip in $ipv4_ips; do
                if [[ "$ip" == "$default_ip" ]]; then
                    echo "$default_ip"
                    return 0
                fi
            done
        fi
        
        # Get the default interface
        local default_iface=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}')
        if [[ -n "$default_iface" ]]; then
            local iface_ip=$(ip -br -4 addr show "$default_iface" 2>/dev/null | awk '{print $3}' | awk -F/ '{print $1}')
            if [[ -n "$iface_ip" ]]; then
                for ip in $ipv4_ips; do
                    if [[ "$ip" == "$iface_ip" ]]; then
                        echo "$iface_ip"
                        return 0
                    fi
                done
            fi
        fi
        
        # Get all interfaces with their IPs
        local iface_data=$(ip -br -4 addr show 2>/dev/null)
        if [[ -n "$iface_data" ]]; then
            # Process each interface
            while IFS= read -r line; do
                local iface=$(echo "$line" | awk '{print $1}')
                local state=$(echo "$line" | awk '{print $2}')
                local ip_cidr=$(echo "$line" | awk '{print $3}' | awk -F/ '{print $1}')
                
                # Skip loopback, docker, bridge interfaces
                if [[ "$iface" == "lo" || "$iface" == docker* || "$iface" == br-* || 
                      "$iface" == virbr* || "$iface" == *_gwbridge || "$iface" == vxlan* ]]; then
                    continue
                fi
                
                # Skip interfaces that aren't UP
                if [[ "$state" != "UP" ]]; then
                    continue
                fi
                
                if [[ -n "$ip_cidr" ]]; then
                    for ip in $ipv4_ips; do
                        if [[ "$ip" == "$ip_cidr" ]]; then
                            echo "$ip_cidr"
                            return 0
                        fi
                    done
                fi
            done <<< "$iface_data"
        fi
    fi
    
    # 4. Last resort - first non-loopback, non-link-local IP
    for ip in $ipv4_ips; do
        if [[ ! "$ip" =~ ^127\. && ! "$ip" =~ ^169\.254\. ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    # Fallback to loopback if nothing else
    echo "$loopback_ip"
}

setup_head_env() {
    set_env_value "KAMIWAZA_CLUSTER_MEMBER" "true"
    set_env_value "KAMIWAZA_INSTALL_ROOT" "${KAMIWAZA_ROOT}"
    set_env_value "KAMIWAZA_SWARM_HEAD" "true"
    set_env_value "KAMIWAZA_ORIG_NODE_TYPE" "head"
    
    # Get a single IP address using our best_ip_for_hostname function
    local head_ip=$(best_ip_for_hostname)
    set_env_value "KAMIWAZA_HEAD_IP" "$head_ip"
    
    set_env_value "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION" "python"
}

setup_worker_env() {
    set_env_value "KAMIWAZA_CLUSTER_MEMBER" "true"
    set_env_value "KAMIWAZA_INSTALL_ROOT" "${KAMIWAZA_ROOT}"
    set_env_value "KAMIWAZA_HEAD_IP" "${KAMIWAZA_HEAD_IP}"
    set_env_value "KAMIWAZA_SWARM_TARGET" "${KAMIWAZA_HEAD_IP}"
    set_env_value "PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION" "python"
    set_env_value "KAMIWAZA_ORIG_NODE_TYPE" "worker"
}

# Function to be placed in common.sh or similar
setup_docker_root() {
    if [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]] || [[ "$(uname)" == "Darwin" ]]; then
        return 0
    fi

    local target_root="$1"
    local current_root=""
    
    # Check if Docker daemon.json exists and get current data-root
    if [ -f "/etc/docker/daemon.json" ]; then
        current_root=$(grep -o '"data-root":[[:space:]]*"[^"]*"' /etc/docker/daemon.json | cut -d'"' -f4)
    fi

    # If current_root matches target_root, nothing to do
    if [ "$current_root" = "$target_root" ]; then
        print_in_color green "Docker data-root already correctly configured at $target_root"
        return 0
    fi

    # Create target directories with correct permissions
    sudo mkdir -p "${target_root}"/{buildkit,image,network,plugins,swarm,tmp,volumes,overlay2,runtimes}
    sudo mkdir -p "${target_root}/network/files"
    for dir in buildkit image network plugins swarm tmp runtimes; do
        sudo chown root:root "${target_root}/$dir"
        sudo chmod 700 "${target_root}/$dir"  # drwx------
    done

    sudo chown root:root "${target_root}/buildkit"
    sudo chmod 711 "${target_root}/buildkit"  # drwx--x--x

    sudo chown root:root "${target_root}/network"
    sudo chmod 750 "${target_root}/network"   # drwxr-x---
    sudo chown root:root "${target_root}/network/files"
    sudo chmod 750 "${target_root}/network/files"  # drwxr-x---

    sudo chown root:root "${target_root}/volumes"
    sudo chmod 751 "${target_root}/volumes"   # drwxr-x--x

    sudo chown root:root "${target_root}/overlay2"
    sudo chmod 710 "${target_root}/overlay2"  # drwx--x---

    # Base directory
    sudo chown root:root "$target_root"
    sudo chmod 710 "${target_root}"   

    # Prepare new Docker configuration
    local docker_config='{
    "data-root": "'$target_root'",
    "features": {
        "buildkit": true
    },
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}'

    # If we have a current root and it's different, we need to migrate
    if [ -n "$current_root" ] && [ "$current_root" != "$target_root" ] && [ -d "$current_root" ]; then
        print_in_color yellow "Migrating Docker root from $current_root to $target_root"
        
        # Stop Docker first
        if systemctl is-active --quiet docker; then
            sudo systemctl stop docker
        fi

        # Only migrate if source exists and has contents
        if [ -d "$current_root" ] && [ "$(ls -A $current_root)" ]; then
            print_in_color yellow "Copying existing Docker data..."
            # Use rsync with --remove-source-files only for files we can delete
            sudo rsync -av --ignore-existing "$current_root/" "$target_root/"
            
            # Create backup of old root
            local backup_dir="${current_root}_backup_$(date +%Y%m%d_%H%M%S)"
            sudo mv "$current_root" "$backup_dir"
            print_in_color yellow "Old Docker root backed up to $backup_dir"
        fi
    fi

    # Update Docker configuration
    sudo mkdir -p /etc/docker
    echo "$docker_config" | sudo tee /etc/docker/daemon.json > /dev/null

    # Start Docker if it was stopped
    if ! systemctl is-active --quiet docker; then
        sudo systemctl start docker
    else
        sudo systemctl restart docker
    fi

    print_in_color green "Docker data-root configuration completed"
}

setup_network_prereqs() {
    if [[ "${KAMIWAZA_COMMUNITY:-}" == "true" ]] || [[ "$(uname)" == "Darwin" ]]; then
        return 0
    fi 

    # Set up required kernel modules if not already configured
    if [[ ! -f /etc/modules-load.d/kamiwaza.conf ]]; then
        print_in_color green "Configuring kernel modules..."
        sudo tee /etc/modules-load.d/kamiwaza.conf <<EOF
overlay
br_netfilter
EOF
    fi

    # Set up sysctl if not already configured
    if [[ ! -f /etc/sysctl.d/kamiwaza.conf ]]; then
        print_in_color green "Configuring sysctl..."
        sudo tee /etc/sysctl.d/kamiwaza.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    fi

    # Verify/load modules
    if ! lsmod | grep -q br_netfilter || ! lsmod | grep -q overlay; then
        print_in_color yellow "Loading required kernel modules..."
        sudo modprobe overlay
        sudo modprobe br_netfilter
    fi

    # Verify/apply sysctl settings
    local need_sysctl=0
    for setting in net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward; do
        if [[ $(sysctl -n $setting 2>/dev/null || echo 0) != 1 ]]; then
            need_sysctl=1
            break
        fi
    done

    if [[ $need_sysctl -eq 1 ]]; then
        print_in_color yellow "Applying sysctl settings..."
        sudo sysctl --system
    fi

    # If Docker is running, restart it to pick up new settings
    if systemctl is-active --quiet docker; then
        print_in_color yellow "Restarting Docker to apply network settings..."
        sudo systemctl restart docker
    fi
}

promote_nvm_node() {
    # Ensure NVM_DIR is set based on installation type
    if [[ "${KAMIWAZA_COMMUNITY:-}" != "true" ]]; then
        export NVM_DIR="/opt/kamiwaza/nvm"
    else
        export NVM_DIR="$HOME/.nvm"
    fi

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

verify_node_version() {
    if ! command -v node &> /dev/null; then
        return 1
    fi
    
    node_version=$(node --version)
    if [[ ! "$node_version" =~ ^v22 ]]; then
        return 1
    fi
    
    return 0
}

ensure_correct_node() {
    local max_attempts=3
    local attempt=1
    
    # Set NVM_DIR based on installation type
    if [[ "${KAMIWAZA_COMMUNITY:-}" != "true" ]]; then
        export NVM_DIR="/opt/kamiwaza/nvm"
    else
        export NVM_DIR="$HOME/.nvm"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        if verify_node_version; then
            return 0
        fi
        
        if [ $attempt -eq 1 ]; then
            promote_nvm_node
            hash -r  # Clear command path cache
        fi
        
        nvm install 22
        nvm alias default 22
        nvm use 22
        
        ((attempt++))
    done
    
    return 1
}