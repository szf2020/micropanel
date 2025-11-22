#!/bin/sh

# Start touch-gallery and prepare to fetch image list
# Usage: ./fetch-images.sh --launcher=127.0.0.1:8081 --touch-gallery=127.0.0.1:8086

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default values
LAUNCHER_ADDR="127.0.0.1:8081"
GALLERY_ADDR="127.0.0.1:8086"
TIMEOUT=2

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --launcher=*)
            LAUNCHER_ADDR="${arg#*=}"
            ;;
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

# Check if touch-gallery is running
check_gallery_running() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$GALLERY_ADDR" --command=get-count --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && [ -n "$response" ] && ! echo "$response" | grep -qi "error"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

echo "Fetching image list..."

# Check if gallery is already running
if check_gallery_running; then
    # Already running - list is ready
    echo "Gallery running"
    echo "Image list ready!"
    exit 0
fi

# Gallery not running - start it
echo "Starting gallery..."

# Stop any currently running app to free up launcher slot
"$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=stop-app --timeoutsec="$TIMEOUT" >/dev/null 2>&1
sleep 0.5

# Start touch-gallery
response=$("$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=start-app --command-arg=gallery --timeoutsec="$TIMEOUT" 2>&1)

if [ $? -eq 0 ] && echo "$response" | grep -q "OK"; then
    # Wait for app to initialize
    sleep 2
    
    # Verify it's responding
    if check_gallery_running; then
        echo "Gallery started!"
        echo "Re-enter Images menu"
        echo "to see image list"
        exit 0
    else
        echo "Gallery started but"
        echo "not responding yet"
        exit 1
    fi
else
    echo "Failed to start"
    echo "Check launcher"
    exit 1
fi
