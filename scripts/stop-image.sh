#!/bin/sh
# Stop touch-gallery via launcher socket API
# Compatible with busybox and standard Linux environments

# Default values
LAUNCHER="127.0.0.1:8081"
GALLERY="127.0.0.1:8086"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --launcher=*)
            LAUNCHER="${1#*=}"
            ;;
        --touch-gallery=*)
            GALLERY="${1#*=}"
            ;;
    esac
    shift
done

echo "Stopping image playback"

# Extract host and port from LAUNCHER
LAUNCHER_HOST="${LAUNCHER%:*}"
LAUNCHER_PORT="${LAUNCHER#*:}"

# Stop touch-gallery via launcher
RESPONSE=$(echo "stop-app gallery" | nc "$LAUNCHER_HOST" "$LAUNCHER_PORT" 2>/dev/null)

if [ "$RESPONSE" = "OK" ]; then
    echo "Touch-gallery stopped successfully"
    exit 0
else
    # Fallback: try to quit via gallery socket directly
    GALLERY_HOST="${GALLERY%:*}"
    GALLERY_PORT="${GALLERY#*:}"

    echo "quit" | nc "$GALLERY_HOST" "$GALLERY_PORT" > /dev/null 2>&1
    echo "Sent quit command to touch-gallery"
    exit 0
fi
