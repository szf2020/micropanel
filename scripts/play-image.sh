#!/bin/sh
# Display image via touch-gallery socket API
# Compatible with busybox and standard Linux environments

# Check if a filename was provided
if [ -z "$1" ]; then
    echo "Error: No image file specified"
    exit 1
fi

IMAGE_FILE="$1"
IMAGE_DIR="${2:-}"

# Default values
LAUNCHER=""
GALLERY="127.0.0.1:8086"

# Parse remaining command line arguments
shift 2 2>/dev/null || shift 1 2>/dev/null || true
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

# Extract host and port from GALLERY
GALLERY_HOST="${GALLERY%:*}"
GALLERY_PORT="${GALLERY#*:}"

# Extract host and port from LAUNCHER (if provided)
if [ -n "$LAUNCHER" ]; then
    LAUNCHER_HOST="${LAUNCHER%:*}"
    LAUNCHER_PORT="${LAUNCHER#*:}"

    # Optionally start touch-gallery via launcher
    # Check if touch-gallery is responding first
    if ! echo "get-count" | nc -w 1 "$GALLERY_HOST" "$GALLERY_PORT" > /dev/null 2>&1; then
        # touch-gallery not responding, try to start it via launcher
        echo "start-app gallery" | nc "$LAUNCHER_HOST" "$LAUNCHER_PORT" > /dev/null 2>&1
        # Give it time to start
        sleep 1
    fi
fi

# If directory specified, set it first
if [ -n "$IMAGE_DIR" ]; then
    RESPONSE=$(echo "set-directory $IMAGE_DIR" | nc "$GALLERY_HOST" "$GALLERY_PORT" 2>/dev/null)
    if [ "$RESPONSE" != "OK" ]; then
        echo "Error: Failed to set directory to $IMAGE_DIR"
        exit 1
    fi
fi

# Send display command to touch-gallery
RESPONSE=$(echo "display $IMAGE_FILE" | nc "$GALLERY_HOST" "$GALLERY_PORT" 2>/dev/null)

if [ "$RESPONSE" = "OK" ]; then
    echo "Displaying image: $IMAGE_FILE"
    exit 0
else
    echo "Error: Failed to display image '$IMAGE_FILE' - $RESPONSE"
    exit 1
fi
