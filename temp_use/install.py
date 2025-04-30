# Steps for Successful Install

# 1. Test for requirements.txt
# 2. Test for config file
# 3. Test for Docker files
# 4. Test for/launch containers
# 5. Create databases
# 6. License stuff?

import os
import re
import importlib.metadata
import sys
import subprocess
import time
from typing import Optional, Tuple
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend
from util.generate_jwt_keys import generate_jwt_keys

# Set PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION to use pure-Python parsing
os.environ['PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION'] = 'python'

def print_in_color(color: str, message: str) -> None:
    """Print a message in the specified color."""
    colors = {
        'red': '\033[91m',
        'green': '\033[92m',
        'yellow': '\033[93m',
        'blue': '\033[94m',
        'reset': '\033[0m'
    }
    print(f"{colors.get(color, '')}{message}{colors['reset']}")

def parse_requirement(req: str) -> Tuple[str, Optional[str], Optional[str]]:
    """Parse a requirement string into name, min version, and max version."""
    parts = req.split(',')
    name = parts[0].split('>=')[0].split('==')[0].strip()
    min_version = max_version = None
    for part in parts:
        if '>=' in part:
            min_version = part.split('>=')[1].strip()
        elif '<' in part:
            max_version = part.split('<')[1].strip()
    return name, min_version, max_version

def get_installed_version(package_name: str) -> Optional[str]:
    """Get the installed version of a package."""
    try:
        # Strip out extras (e.g., 'ray[default,serve]' -> 'ray')
        package_name = re.split(r'\[|\]', package_name)[0]
        return importlib.metadata.version(package_name)
    except importlib.metadata.PackageNotFoundError:
        return None
    except Exception as e:
        print_in_color('red', f"Error parsing requirement for {package_name}: {e}")
        return None
# Ensure the script is invoked from install.sh or setup.sh
if not os.getenv('KAMIWAZA_RUN_FROM_INSTALL'):
    print_in_color('red', "Warning: This script should not be run directly.")
    print("Please run install.sh or setup.sh instead.")
    print("If you know what you are doing and have been instructed to run this script directly, set the environment variable 'KAMIWAZA_RUN_FROM_INSTALL=yes' and try again.")
    sys.exit(1)

# Check if we are in a virtual environment
if hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix):
    print_in_color('green', f"Virtual environment detected: {sys.prefix}")
else:
    print_in_color('red', "Warning: Not running in a virtual environment - careful")
    if '-y' not in sys.argv:
        user_input = input("Do you want to continue without a virtual environment? Type 'yes' to proceed: ")
        if user_input.lower() != 'yes':
            print("Exiting the installation.")
            sys.exit(1)

# Define the paths to check for requirements.txt
paths_to_check = ['../requirements.txt', './requirements.txt']


# Rest of the script remains unchanged
###### 2. Test for config fiels
print("**** Testing for expected config files...")

# Define the paths to check for config files, removing the leading './' for proper concatenation later
config_paths_to_check = [
    'kamiwaza/cluster/config.py',
    'kamiwaza/serving/config.py',
    'kamiwaza/node/config.py',
    'kamiwaza/services/catalog/config.py',
    'kamiwaza/services/vectordb/config.py',
    'kamiwaza/services/models/config.py',
    'kamiwaza/services/retrieval/config.py',
    'kamiwaza/services/prompts/config.py'
]

def get_site_packages_path(venv_path: Optional[str] = None) -> Optional[str]:
    """
    Retrieves the site-packages path from the virtual environment if available.
    
    Args:
        venv_path: The path to the virtual environment.
        
    Returns:
        The site-packages path if the virtual environment is detected, otherwise None.
    """
    if venv_path:
        return os.path.join(venv_path, 'lib', f"python{sys.version_info.major}.{sys.version_info.minor}", 'site-packages')
    return None

def check_config_path(config_path: str, site_packages_path: Optional[str] = None) -> None:
    """
    Checks if the config file exists at the given path or within the site-packages directory.
    
    Args:
        config_path: The path to the config file to check.
        site_packages_path: The site-packages directory path.
    """
    # Check directly in the provided path
    if os.path.isfile(config_path):
        print_in_color('green', f"{config_path}: Yes")
    # Construct the path within the site-packages and check
    elif site_packages_path:
        # Construct the path relative to the site-packages directory
        venv_config_path = os.path.join(site_packages_path, config_path)
        if os.path.isfile(venv_config_path):
            print_in_color('green', f"{config_path} (in venv): Yes")
        else:
            print_in_color('red', f"{config_path}: No")
    else:
        print_in_color('red', f"{config_path}: No")

# Retrieve the virtual environment path from the environment variable
venv_path = os.getenv('VIRTUAL_ENV')
site_packages_path = get_site_packages_path(venv_path)

# Iterate over the config paths
for config_path in config_paths_to_check:
    check_config_path(config_path, site_packages_path)


##### Generate JWT keypair
print("*** Generating JWT keypair...")

runtime_dir = os.path.join(os.path.dirname(__file__), 'runtime')
generate_jwt_keys(runtime_dir)

##### 3. Install the containers
print("*** Composing docker containers... ")

# launch the containers, because we need them up for the install
try:
    result = subprocess.run(['./containers-up.sh'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout.decode('utf-8'))
except Exception as e:
    print(f"Failed to run containers-up.sh: {e}")
    pass

print("*** Waiting for containers to start...")
time.sleep(15)

print("*** Ensuring containers are up")
try:
    result = subprocess.run(['./containers-up.sh'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout.decode('utf-8'))
except Exception as e:
    print(f"Failed to run containers-up.sh: {e}")
    print("Second pass container failure: FATAL. Contact support@kamiwaza.ai")
    exit(1)



#import here because we need the containers up to avoid a cockroach error

from util.admin_db_reset import reset_all_databases
##### 5. Create databases
print("*** Initializing Database...")
# Initialize all databases in non-destructive mode
reset_all_databases(reset_db=False, skip_confirmation=True)
