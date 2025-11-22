#!/bin/sh

# List available images from Pictures directory
# Usage: ./list-images.sh --image-dir=/path/to/images

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default image directory
IMAGE_DIR="$MICROPANEL_HOME/share/qt-apps/Pictures"

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --image-dir=*)
            IMAGE_DIR="${arg#*=}"
            ;;
        *)
            # Ignore unknown arguments
            ;;
    esac
done

# List all image files in the directory
# Supports: jpg, jpeg, png, gif, bmp
if [ -d "$IMAGE_DIR" ]; then
    cd "$IMAGE_DIR" || exit 1

    # Output "off" first (like pattern menu)
    echo "off"

    # List image files, one per line, sorted
    ls -1 *.jpg *.jpeg *.png *.gif *.bmp 2>/dev/null | sort
else
    # Directory doesn't exist - return nothing
    exit 1
fi

exit 0
