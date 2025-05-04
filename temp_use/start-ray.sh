#!/bin/bash

# On the server/cluster side where Ray is started:
export RAY_LOGGING_LEVEL=WARNING
export RAY_LOGGING_FORMAT="{message}"  # Simplifies format
export RAY_LOG_TO_DRIVERS=0  # This is key - prevents forwarding logs to clients

if [ -f "kamiwaza-shibboleth" ] && [ "$KAMIWAZA_DEBUG_RAY" = "true" ]; then
    export RAY_LOG_TO_DRIVERS=1
fi

source set-kamiwaza-root.sh

# Function to check if a directory meets the criteria and can be written to
check_directory() {
    local dir=$1
    local min_size=$2
    
    # For /tmp subdirectories, check if parent is a mountpoint
    if [[ "$dir" == */tmp ]]; then
        local parent_dir=${dir%/tmp}
        if [ ! -d "$parent_dir" ] || [ ! mountpoint -q "$parent_dir" ]; then
            return 1
        fi
    elif [ ! -d "$dir" ] || [ ! mountpoint -q "$dir" ]; then
        return 1
    fi

    local free_space=$(df -BG "$dir" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$free_space" -ge "$min_size" ]; then
        # Check if we can create a directory
        local test_dir="$dir/ray_temp_test"
        if mkdir -p "$test_dir" 2>/dev/null; then
            rm -rf "$test_dir"
            echo "$dir"
            return 0
        fi
    fi
    return 1
}

# Check config file for worker status
if [ -f "/etc/kamiwaza/config/is_worker" ]; then
    IS_WORKER=$(tr -cd '[:alnum:]' < /etc/kamiwaza/config/is_worker | tr '[:upper:]' '[:lower:]')
    if [ "$IS_WORKER" = "1" ] || [ "$IS_WORKER" = "true" ]; then
        export KAMIWAZA_WORKER=1
    fi
elif [ -n "${KAMIWAZA_HEAD_IP}" ]; then
    ifconfig | grep 'inet ' | awk '{print $2}' | grep -Fx "${KAMIWAZA_HEAD_IP}" > /dev/null 2>&1
    IS_WORKER=$?
    if [ $IS_WORKER -ne 0 ]; then
        export KAMIWAZA_WORKER=1
    fi
fi



if [ -n "$KAMIWAZA_WORKER" ] ; then
    if [ -f "/etc/kamiwaza/config/head_ip" ] ; then
        FILE_HEAD_IP=$(tr -cd '[:alnum:].:' < /etc/kamiwaza/config/head_ip | tr -d '[:space:]')
    fi
    if [ -z "$KAMIWAZA_HEAD_IP" -a ! -z "$FILE_HEAD_IP" ] ; then
        KAMIWAZA_HEAD_IP=${FILE_HEAD_IP}
    fi
    if [ -z "$KAMIWAZA_HEAD_IP" ] ; then
        echo "KAMIWAZA_HEAD_IP is not set, but KAMIWAZA_WORKER is set -  you MUST pass it or place it in /etc/kamiwaza/config/head_ip"
        exit 1
    fi
    # Check if running on Darwin (macOS) - we don't support workers on macOS
    if [[ "$OSTYPE" == "darwin"* ]] || [[ "$(uname -s)" == "Darwin" ]]; then
        echo "ERROR: Ray workers are not supported on macOS/Darwin systems"
        exit 1
    fi
    if [ -n "$KAMIWAZA_ROOT" ] ; then
        touch $KAMIWAZA_ROOT/ray-is-worker
    fi
fi

# Function to set RAY_TEMP_DIR
set_ray_temp_dir() {
    local directories=(
        "/mnt/tmp"
        "/scratch1" "/scratch2" "/scratch3" "/scratch4" "/scratch5" "/scratch6" "/scratch7" "/scratch8" "/scratch9"
        "/mnt"
        "/opt/kamiwaza"
        "/tmp"
    )
    local selected_dir=""

    for dir in "${directories[@]}"; do
        # Touch a random file to ensure the directory is writable
        local test_file="$dir/ray_temp_test_file"
        if touch "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            if selected_dir=$(check_directory "$dir" 60); then
                echo "Selected $dir"
                break
            fi
        fi
    done

    # If a directory was selected, set up Ray temp directory
    if [ -n "$selected_dir" ]; then
        export RAY_TEMP_DIR="$selected_dir/ray_temp"
        if mkdir -p "$RAY_TEMP_DIR"; then
            # Determine env file location
            if [ -f "${KAMIWAZA_ROOT}/env.sh" ]; then
                env_file="${KAMIWAZA_ROOT}/env.sh"
            elif [ -f "/etc/kamiwaza/env.sh" ]; then
                env_file="/etc/kamiwaza/env.sh"
            else
                echo "No env.sh file found in ${KAMIWAZA_ROOT} or /etc/kamiwaza"
                return 1
            fi

            # Remove any existing RAY_TEMP_DIR exports from env file
            sed -i '/^export RAY_TEMP_DIR=/d' "$env_file"
            
            # Add export to env file
            echo "export RAY_TEMP_DIR=$RAY_TEMP_DIR" >> "$env_file"
            
            # Create or update ray.yaml
            mkdir -p ~/.ray
            echo "temp_dir: $RAY_TEMP_DIR" > ~/.ray/ray.yaml
            
            echo "Set RAY_TEMP_DIR to $RAY_TEMP_DIR"
        else
            echo "Failed to create $RAY_TEMP_DIR. Using default Ray temporary directory."
            unset RAY_TEMP_DIR
        fi
    else
        echo "No suitable directory found for RAY_TEMP_DIR. Using default Ray temporary directory."
    fi
}

# Call the function to set RAY_TEMP_DIR
set_ray_temp_dir

# Get the directory of the script
script_dir=$(dirname "$(readlink -f "$0")")

# Add script directory to PYTHONPATH if dev file layout
if [[ "$script_dir" == *"kamiwaza"* ]] && [[ ! -f "$script_dir/launch.py" ]]; then
    export PYTHONPATH="${PYTHONPATH}:${script_dir}"
fi

# Activate the virtual environment
if [ ! -f venv/bin/activate ] ; then
    echo "venv/bin/activate not found, you are running from the wrong directory or have not run install.sh"
    exit 1
fi
source venv/bin/activate

export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
export ray_dashboard_host="0.0.0.0"

# Determine the number of CPUs
if [[ "$OSTYPE" == "darwin"* ]]; then
    # On macOS, limit to performance cores if possible
    num_cpus=$(sysctl -n hw.perflevel0.logicalcpu_max)
    if [ -z "$num_cpus" ]; then
        num_cpus=$(sysctl -n hw.ncpu)
    fi
else
    num_cpus=$(grep -c ^processor /proc/cpuinfo)
fi

# Determine the number of GPUs using nvidia-smi, be graceful if it fails
if command -v nvidia-smi &> /dev/null; then
    num_gpus=$(nvidia-smi --list-gpus | wc -l)
elif command -v hl-smi &> /dev/null; then
    # Check for Habana Gaudi GPUs
    num_gpus=$(hl-smi -d MEMORY -Q memory.total -f csv,noheader | wc -l)
else
    num_gpus=0
fi

# Check if running on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # if osx just set the GPUs so high it looks infinite to kamiwaza serving
    num_gpus=999
fi

# Override with environment variables if set
if [ -n "$KAMIWAZA_NUM_CPUS" ]; then
    num_cpus=$KAMIWAZA_NUM_CPUS
fi
if [ -n "$KAMIWAZA_NUM_GPUS" ]; then
    num_gpus=$KAMIWAZA_NUM_GPUS
fi

# Calculate kamiwaza_gpus as 100 * num_gpus
kamiwaza_gpus=$((num_gpus * 100))

# Start ray with appropriate parameters
if [ -n "$KAMIWAZA_HEAD_IP" ] && [ -n "$KAMIWAZA_WORKER" ]; then
    # Worker node configuration
    ray_start_cmd="ray start --num-cpus $num_cpus --address $KAMIWAZA_HEAD_IP:6379 --disable-usage-stats"
else
    # Head node configuration
    ray_start_cmd="ray start --num-cpus $num_cpus --head --dashboard-host 0.0.0.0 --disable-usage-stats"
fi

if [ "$num_gpus" -gt 0 ]; then
    ray_start_cmd+=" --num-gpus $num_gpus"
    ray_start_cmd+=" --resources=\"{\\\"kamiwaza_gpus\\\": $kamiwaza_gpus}\""
fi

if [ -n "$RAY_TEMP_DIR" ]; then
    ray_start_cmd+=" --temp-dir $RAY_TEMP_DIR"
fi

echo "Starting Ray with command: $ray_start_cmd"
eval "$ray_start_cmd"
ray_exit_code=$?

if [ $ray_exit_code -ne 0 ]; then
    echo "Ray failed to start with exit code $ray_exit_code"
fi

exit $ray_exit_code
