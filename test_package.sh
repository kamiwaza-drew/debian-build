#!/bin/bash

# Usage: ./test_package.sh /path/to/package.deb
#        ./test_package.sh /path/to/archive.tar.gz

set -e

PACKAGE="$1"

if [ -z "$PACKAGE" ]; then
    echo "Usage: $0 /path/to/package.deb|archive.tar.gz"
    exit 1
fi

if [ ! -f "$PACKAGE" ]; then
    echo "[ERROR] File not found: $PACKAGE"
    exit 2
fi

if [ ! -s "$PACKAGE" ]; then
    echo "[ERROR] File is empty: $PACKAGE"
    exit 3
fi

echo "[INFO] File exists and is non-empty: $PACKAGE"

case "$PACKAGE" in
    *.deb)
        echo "[INFO] Checking .deb package integrity..."
        if dpkg-deb --info "$PACKAGE" >/dev/null 2>&1; then
            echo "[SUCCESS] .deb package is valid."
        else
            echo "[ERROR] .deb package is corrupt or invalid."
            exit 4
        fi

        # Optional: extract to temp dir
        TMPDIR=$(mktemp -d)
        echo "[INFO] Extracting .deb to $TMPDIR"
        if dpkg-deb -x "$PACKAGE" "$TMPDIR"; then
            echo "[SUCCESS] .deb extracted successfully."
        else
            echo "[ERROR] Failed to extract .deb."
            rm -rf "$TMPDIR"
            exit 5
        fi
        rm -rf "$TMPDIR"
        ;;
    *.tar.gz|*.tgz)
        echo "[INFO] Checking tar.gz archive integrity..."
        if tar -tzf "$PACKAGE" >/dev/null 2>&1; then
            echo "[SUCCESS] tar.gz archive is valid."
        else
            echo "[ERROR] tar.gz archive is corrupt or invalid."
            exit 6
        fi

        # Optional: extract to temp dir
        TMPDIR=$(mktemp -d)
        echo "[INFO] Extracting tar.gz to $TMPDIR"
        if tar -xzf "$PACKAGE" -C "$TMPDIR"; then
            echo "[SUCCESS] tar.gz extracted successfully."
        else
            echo "[ERROR] Failed to extract tar.gz."
            rm -rf "$TMPDIR"
            exit 7
        fi
        rm -rf "$TMPDIR"
        ;;
    *)
        echo "[ERROR] Unsupported file type: $PACKAGE"
        exit 8
        ;;
esac

echo "[INFO] Package test completed successfully."
exit 0