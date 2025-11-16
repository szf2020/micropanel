#!/bin/sh

# Extended micropanel version script
# Reads from multiple version files and formats output for SSD1306 display (4 lines max)
# Compatible with /bin/sh (POSIX) - works on buildroot busybox and Raspberry Pi OS

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Initialize variables
base_version=""
incr_version=""
upanel_version=""
build_date=""
build_time=""

# Read base version if available
if [ -f "/etc/base-version.txt" ]; then
    base_version=$(grep '^VERSION=' /etc/base-version.txt 2>/dev/null | cut -d'=' -f2)
fi

# Read incremental version if available
if [ -f "/etc/incremental-version.txt" ]; then
    incr_version=$(grep '^VERSION=' /etc/incremental-version.txt 2>/dev/null | cut -d'=' -f2)
    # Extract build date/time from incremental version (most recent)
    build_datetime=$(grep '^BUILD_DATE=' /etc/incremental-version.txt 2>/dev/null | cut -d'=' -f2)
    if [ -n "$build_datetime" ]; then
        # Format: 2025-11-16_15:20:10_UTC
        # Extract date part (2025-11-16)
        build_date=$(echo "$build_datetime" | cut -d'_' -f1)
        # Extract time part (15:20:10) and trim to HH:MM
        build_time=$(echo "$build_datetime" | cut -d'_' -f2 | cut -d':' -f1-2)
    fi
fi

# Read micropanel version with priority lookup
if [ -f "$MICROPANEL_HOME/configs/version.txt" ]; then
    upanel_version=$(cat "$MICROPANEL_HOME/configs/version.txt")
elif [ -f "$MICROPANEL_HOME/etc/micropanel/version.txt" ]; then
    upanel_version=$(cat "$MICROPANEL_HOME/etc/micropanel/version.txt")
elif [ -f "/etc/micropanel/version.txt" ]; then
    upanel_version=$(cat "/etc/micropanel/version.txt")
fi

# Output in Option A format (4 lines max for SSD1306)
# Only output lines for available data

if [ -n "$base_version" ]; then
    echo "Base: $base_version"
fi

if [ -n "$incr_version" ]; then
    echo "Incr: $incr_version"
fi

if [ -n "$upanel_version" ]; then
    echo "uPanel: $upanel_version"
fi

if [ -n "$build_date" ] && [ -n "$build_time" ]; then
    echo "$build_date $build_time"
elif [ -n "$build_date" ]; then
    echo "$build_date"
fi

# If nothing was found, output fallback
if [ -z "$base_version" ] && [ -z "$incr_version" ] && [ -z "$upanel_version" ]; then
    echo "No version info"
fi

exit 0
