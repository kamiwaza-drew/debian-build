# Kamiwaza Debian Package

This repository contains the Debian packaging files for Kamiwaza AI Platform.

## Building the Package

### Prerequisites

- Debian/Ubuntu system
- `dpkg-dev` package
- `debhelper` package

### Build Steps

1. Clone the repository:
```bash
git clone https://github.com/kamiwaza-drew/debian-build.git
cd debian-build
```

2. Build the package:
```bash
cd kamiwaza-deb
dpkg-buildpackage -us -uc
```

The built package will be created in the parent directory as `kamiwaza_0.3.3-1_amd64.deb`.

### Installation

1. Install the package:
```bash
sudo dpkg -i ../kamiwaza_0.3.3-1_amd64.deb
```

2. If there are missing dependencies:
```bash
sudo apt --fix-broken install
```

### Package Structure

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

### Updating Version

1. Update version in `kamiwaza-deb/debian/changelog`
2. Update version in `kamiwaza-deb/debian/control` if needed

## License

Proprietary - All rights reserved 