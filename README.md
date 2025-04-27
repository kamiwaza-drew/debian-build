# Kamiwaza Debian Package

This repository contains the Debian packaging files for Kamiwaza AI Platform. The package automates the installation of Kamiwaza and all its dependencies on Ubuntu systems.

## Features

- Automatic installation of all required dependencies
- Systemd service integration
- NVIDIA driver and Docker configuration
- Automatic download and installation of the latest Kamiwaza release

## Prerequisites

- Ubuntu 22.04 LTS or later
- `dpkg-dev` package
- `debhelper` package
- sudo privileges

## Building the Package

1. Clone the repository:
```bash
git clone https://github.com/kamiwaza-drew/debian-build.git
cd debian-build
```

2. Install build dependencies:
```bash
sudo apt install -y dpkg-dev debhelper
```

3. Build the package:
```bash
cd kamiwaza-deb
dpkg-buildpackage -us -uc
```
<!-- Add documentation on when to use:
cd ~/debian-packaging/kamiwaza-deb && sudo dpkg-buildpackage -us -uc -rfakeroot -->
Additionally, if you're building the package in a non-standard environment or without proper permissions, you may need to use fakeroot:

```bash
cd ~/debian-packaging/kamiwaza-deb && sudo dpkg-buildpackage -us -uc -rfakeroot
```

The built package will be created in the parent directory as `kamiwaza_0.3.3-1_amd64.deb`.

## Installation

1. Install the package:
```bash
sudo dpkg -i ../kamiwaza_0.3.3-1_amd64.deb
```

2. If there are missing dependencies:
```bash
sudo apt --fix-broken install
```

The installation process will:
- Download and install all required dependencies
- Set up Docker and NVIDIA drivers (if applicable)
- Download and extract the latest Kamiwaza release
- Run the installation script
- Configure and start the Kamiwaza service

## Package Structure

- `kamiwaza-deb/debian/control`: Package metadata and dependencies
- `kamiwaza-deb/debian/rules`: Build instructions
- `kamiwaza-deb/debian/changelog`: Version history
- `kamiwaza-deb/debian/copyright`: License information
- `kamiwaza-deb/debian/kamiwaza.postinst`: Post-installation script
- `kamiwaza-deb/debian/kamiwaza.postrm`: Post-removal script
- `kamiwaza-deb/debian/kamiwaza.prerm`: Pre-removal script

## Development

### Adding New Dependencies

Edit `kamiwaza-deb/debian/control` to add new dependencies. Use:
- `Depends:` for required dependencies
- `Recommends:` for optional dependencies

### Changing Download Directory
In the postinst file, there is a line that says ```INSTALL_DIR="/opt/kamiwaza"``` this will need to be changed to alter the default dir.

### Updating Version

1. Update version in `kamiwaza-deb/debian/changelog`
2. Update version in `kamiwaza-deb/debian/control` if needed

## Troubleshooting

If you encounter any issues during installation:
1. Check the system logs: `journalctl -u kamiwaza`
2. Verify service status: `systemctl status kamiwaza`
3. Check installation directory: `/opt/kamiwaza`

## License

Proprietary - All rights reserved 