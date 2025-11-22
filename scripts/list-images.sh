#!/bin/sh
# List images from touch-gallery via socket API
# Compatible with busybox and standard Linux environments

# Default values
LAUNCHER=""
GALLERY="127.0.0.1:8086"
IMAGE_DIR=""

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --launcher=*)
            LAUNCHER="${1#*=}"
            ;;
        --touch-gallery=*)
            GALLERY="${1#*=}"
            ;;
        *)
            # First positional argument is image directory (optional)
            if [ -z "$IMAGE_DIR" ]; then
                IMAGE_DIR="$1"
            fi
            ;;
    esac
    shift
done

# Extract host and port from GALLERY
GALLERY_HOST="${GALLERY%:*}"
GALLERY_PORT="${GALLERY#*:}"

# If directory specified, set it first
if [ -n "$IMAGE_DIR" ]; then
    echo "set-directory $IMAGE_DIR" | nc "$GALLERY_HOST" "$GALLERY_PORT" > /dev/null 2>&1
fi

# Query touch-gallery for image list
RESULT=$(echo "list-images" | nc "$GALLERY_HOST" "$GALLERY_PORT" 2>/dev/null)

# Check if we got a result
if [ -z "$RESULT" ]; then
    # No images found or connection failed
    exit 0
fi

# Convert comma-separated list to newline-separated
echo "$RESULT" | tr ',' '\n'

exit 0
