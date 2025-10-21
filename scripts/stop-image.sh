#!/bin/sh

# Stop Image Playback Script for MicroPanel
# Clears the framebuffer and resets last played image tracking
# Compatible with /bin/sh (POSIX) - works on buildroot busybox and Raspberry Pi OS

echo "Stopping image playback"

# Clear framebuffer (remove sudo since micropanel typically runs as root in buildroot)
# If running as non-root user (Pi OS), this may require sudo permissions
if [ -c /dev/fb0 ]; then
    dd if=/dev/zero of=/dev/fb0 bs=1M count=1 > /dev/null 2>&1 || true
fi

# Clear the last played image file
echo "" > /tmp/last_played_image

exit 0
