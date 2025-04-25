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
git clone https://github.com/kamiwaza-ai/kamiwaza-deb.git
cd kamiwaza-deb
```

2. Build the package:
```bash
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

- `debian/control`: Package metadata and dependencies
- `debian/rules`: Build instructions
- `debian/changelog`: Version history
- `debian/copyright`: License information
- `debian/kamiwaza.postinst`: Post-installation script
- `debian/kamiwaza.postrm`: Post-removal script
- `debian/kamiwaza.prerm`: Pre-removal script

## Development

### Adding New Dependencies

Edit `debian/control` to add new dependencies. Use:
- `Depends:` for required dependencies
- `Recommends:` for optional dependencies

### Updating Version

1. Update version in `debian/changelog`
2. Update version in `debian/control` if needed

## License

Proprietary - All rights reserved 