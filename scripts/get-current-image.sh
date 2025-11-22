#!/bin/sh
# Get currently displayed image from touch-gallery via socket API
# Compatible with busybox and standard Linux environments

# Default values
GALLERY="127.0.0.1:8086"

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --touch-gallery=*)
            GALLERY="${1#*=}"
            ;;
    esac
    shift
done

# Extract host and port from GALLERY
GALLERY_HOST="${GALLERY%:*}"
GALLERY_PORT="${GALLERY#*:}"

# Query touch-gallery for current image
RESULT=$(echo "get-image" | nc "$GALLERY_HOST" "$GALLERY_PORT" 2>/dev/null)

# Return the filename (empty if no image loaded)
echo "$RESULT"

exit 0
