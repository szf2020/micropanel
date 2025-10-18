#!/bin/sh

# This script reads the micropanel version from version.txt
# Priority: $MICROPANEL_HOME/configs/version.txt -> /etc/micropanel/version.txt

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Check for version.txt in order of priority
if [ -f "$MICROPANEL_HOME/configs/version.txt" ]; then
    # Development/local installation
    cat "$MICROPANEL_HOME/configs/version.txt"
elif [ -f "/etc/micropanel/version.txt" ]; then
    # System-wide installation
    cat "/etc/micropanel/version.txt"
else
    # Fallback if no version file found
    echo "unknown"
fi

exit 0
