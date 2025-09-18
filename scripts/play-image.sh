#!/bin/sh

# Check if a filename was provided
if [ -z "$1" ]; then
    echo "Error: No image file specified"
    exit 1
fi

# Set image directory (use default if not provided)
IMAGE_DIR="${2:-/media/files/path}"

# Find the full path to the image
IMAGE_PATH="$IMAGE_DIR/$1"

# Check if file exists
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Error: Image file '$IMAGE_PATH' not found"
    exit 1
fi

# Display the image
echo "Displaying image: $IMAGE_PATH"
# Using fbi (framebuffer imageviewer) to display the image:
fbi -d /dev/fb0 -T 1 -noverbose -a -1 $IMAGE_PATH

# Store the current image as the last played
echo "$1" > /tmp/last_played_image

exit 0
