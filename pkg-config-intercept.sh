#!/bin/bash

# This script temporarily intercepts calls to pkg-config by creating a directory
# early in the PATH and symlinking our custom pkg-config script into it.

set -e  # Exit on any error

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_PKG_CONFIG="$SCRIPT_DIR/custom-pkg-config.sh"
TEMP_BIN_DIR="$SCRIPT_DIR/pkg-config-bin"

# Check if our custom pkg-config exists
if [ ! -f "$CUSTOM_PKG_CONFIG" ]; then
    echo "Error: custom-pkg-config.sh not found at $CUSTOM_PKG_CONFIG" >&2
    exit 1
fi

# Make sure the custom pkg-config is executable
chmod +x "$CUSTOM_PKG_CONFIG"

# Create a temporary bin directory
mkdir -p "$TEMP_BIN_DIR"

# Create a symlink to our custom pkg-config in the temp bin directory
ln -sf "$CUSTOM_PKG_CONFIG" "$TEMP_BIN_DIR/pkg-config"

# Set the environment for pkg-config
export PATH="$TEMP_BIN_DIR:$PATH"
export PKG_CONFIG_ARCH="${PKG_CONFIG_ARCH:-arm64-v8a}"

# Add Qt pkgconfig path to PKG_CONFIG_PATH
QT_PKGCONFIG_PATH="$SCRIPT_DIR/android/tools/qt/5.15.2/android/lib/pkgconfig"
if [ -d "$QT_PKGCONFIG_PATH" ]; then
    if [ -n "$PKG_CONFIG_PATH" ]; then
        export PKG_CONFIG_PATH="$QT_PKGCONFIG_PATH:$PKG_CONFIG_PATH"
    else
        export PKG_CONFIG_PATH="$QT_PKGCONFIG_PATH"
    fi
fi

# Run the command passed as arguments
"$@"
EXIT_CODE=$?

# Clean up
rm -f "$TEMP_BIN_DIR/pkg-config"
rmdir "$TEMP_BIN_DIR"

exit $EXIT_CODE 