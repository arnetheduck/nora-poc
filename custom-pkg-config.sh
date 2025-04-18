#!/bin/bash

# Default target architecture - can be overridden with PKG_CONFIG_ARCH env var
DEFAULT_ARCH="arm64-v8a"  # Options: arm64-v8a, armeabi-v7a, x86, x86_64
TARGET_ARCH="${PKG_CONFIG_ARCH:-$DEFAULT_ARCH}"
QT_DIR="${QT_DIR:-""}"

# Find the real pkg-config binary (avoiding recursion)
# Look in specific system locations first
if [ -x "/usr/bin/pkg-config" ]; then
    ORIGINAL_PKG_CONFIG="/usr/bin/pkg-config"
elif [ -x "/usr/local/bin/pkg-config" ]; then
    ORIGINAL_PKG_CONFIG="/usr/local/bin/pkg-config"
elif [ -x "/opt/homebrew/bin/pkg-config" ]; then
    ORIGINAL_PKG_CONFIG="/opt/homebrew/bin/pkg-config"
else
    # Fallback to searching PATH, carefully excluding our own directory
    THIS_SCRIPT="$(realpath "$0")"
    THIS_DIR="$(dirname "$THIS_SCRIPT")"
    
    # Split PATH and look in each directory
    IFS=: read -ra PATH_DIRS <<< "$PATH"
    ORIGINAL_PKG_CONFIG=""
    
    for dir in "${PATH_DIRS[@]}"; do
        # Skip directories containing our script
        realdir="$(realpath "$dir" 2>/dev/null || echo "$dir")"
        if [ "$realdir" = "$THIS_DIR" ] || [ "$dir" = "$THIS_DIR" ]; then
            continue
        fi
        
        if [ -x "$dir/pkg-config" ]; then
            ORIGINAL_PKG_CONFIG="$dir/pkg-config"
            break
        fi
    done
fi

if [ -z "$ORIGINAL_PKG_CONFIG" ]; then
    echo "Error: Cannot find original pkg-config binary" >&2
    exit 1
fi

# Original args
ORIGINAL_ARGS=("$@")
MODIFIED=0

# Create new args array
NEW_ARGS=()

# Process arguments
for arg in "${ORIGINAL_ARGS[@]}"; do
    # Check if this looks like a Qt module name without architecture suffix
    if [[ "$arg" =~ ^Qt[A-Za-z0-9]+$ && ! "$arg" =~ _[a-z0-9-]+$ ]]; then
        NEW_ARG="${arg}_${TARGET_ARCH}"
        NEW_ARGS+=("$NEW_ARG")
        MODIFIED=1
    else
        NEW_ARGS+=("$arg")
    fi
done

# Execute pkg-config and capture its output
OUTPUT=$("$ORIGINAL_PKG_CONFIG" "${NEW_ARGS[@]}" 2>&1)
EXIT_CODE=$?

# If pkg-config succeeded and output contains hardcoded Qt paths, fix them
if [ $EXIT_CODE -eq 0 ]; then    
    # Replace hardcoded Qt paths with our Qt path
    OUTPUT=$(echo "$OUTPUT" | sed -e "s|/Users/qt/work/install|$QT_DIR|g")
fi


# Send ONLY the output from pkg-config back
echo "$OUTPUT"
exit $EXIT_CODE 