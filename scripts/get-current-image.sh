#!/bin/sh

# Get currently displayed image from touch-gallery app
# Usage: ./get-current-image.sh --touch-gallery=127.0.0.1:8086

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default values
GALLERY_ADDR="127.0.0.1:8086"
TIMEOUT=2

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --touch-gallery=*)
            GALLERY_ADDR="${arg#*=}"
            ;;
        *)
            # Ignore unknown arguments
            ;;
    esac
done

# Auto-detect launcher-client binary location
if [ -n "$LAUNCHER_CLIENT" ] && [ -x "$LAUNCHER_CLIENT" ]; then
    # User explicitly set LAUNCHER_CLIENT - use it
    true
elif [ -x "/usr/bin/launcher-client" ]; then
    # Buildroot: installed to /usr/bin/
    LAUNCHER_CLIENT="/usr/bin/launcher-client"
elif [ -n "$MICROPANEL_HOME" ] && [ -x "$MICROPANEL_HOME/build/launcher-client" ]; then
    # Pi OS: development build
    LAUNCHER_CLIENT="$MICROPANEL_HOME/build/launcher-client"
elif [ -n "$MICROPANEL_HOME" ] && [ -x "$MICROPANEL_HOME/usr/bin/launcher-client" ]; then
    # Pi OS: installed to usr/bin
    LAUNCHER_CLIENT="$MICROPANEL_HOME/usr/bin/launcher-client"
else
    # Fallback: try PATH
    LAUNCHER_CLIENT="launcher-client"
fi

# Query current image
response=$("$LAUNCHER_CLIENT" --srv="$GALLERY_ADDR" --command=get-image --timeoutsec="$TIMEOUT" 2>&1)

if [ $? -eq 0 ] && [ -n "$response" ] && ! echo "$response" | grep -qi "error"; then
    # Got a valid image name
    echo "$response"
else
    # App not running or no image loaded - return "off"
    echo "off"
fi

exit 0
