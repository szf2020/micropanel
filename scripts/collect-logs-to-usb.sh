#!/bin/sh

# Collect logs to USB stick
# Copies log files listed in log-file-list.txt to USB stick
# Compatible with /bin/sh (POSIX) - works on buildroot busybox and Raspberry Pi OS

# USB stick configuration
USB_MOUNT_POINT="/tmp/micropanel-usb"
USB_MOUNTED_BY_SCRIPT=0

# Paths
MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Check if we're running as root - if so, don't use sudo
SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    # Not root, use sudo if available
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    fi
fi

# Detect log-file-list.txt path in multiple locations
# Priority: system install > user install > development
if [ -f "/usr/share/micropanel/configs/log-file-list.txt" ]; then
    # System install (buildroot or package manager)
    LOG_FILE_LIST="/usr/share/micropanel/configs/log-file-list.txt"
elif [ -f "/home/pi/micropanel/usr/share/micropanel/configs/log-file-list.txt" ]; then
    # User install under /home/pi/micropanel/usr/
    LOG_FILE_LIST="/home/pi/micropanel/usr/share/micropanel/configs/log-file-list.txt"
else
    # Development environment
    LOG_FILE_LIST="$MICROPANEL_HOME/configs/log-file-list.txt"
fi

# Print functions (output to stdout for TextBox display)
print_info() {
    printf "%s\n" "$1"
}

print_success() {
    printf "%s\n" "$1"
}

print_error() {
    printf "%s\n" "$1"
}

# Detect USB stick (reusing pattern from flasher scripts)
detect_usb_stick() {
    # Check all /dev/sd* block devices
    for block_dev in /sys/block/sd*; do
        if [ ! -e "$block_dev" ]; then
            continue
        fi

        dev_name=$(basename "$block_dev")
        removable=$(cat "$block_dev/removable" 2>/dev/null || echo "0")

        # Check if it's removable (USB sticks have removable=1)
        if [ "$removable" = "1" ]; then
            # Found a removable device, check for partitions
            for part in "$block_dev"/"$dev_name"*; do
                if [ -e "$part" ]; then
                    part_name=$(basename "$part")
                    if [ "$part_name" != "$dev_name" ]; then
                        echo "/dev/$part_name"
                        return 0
                    fi
                fi
            done

            # No partitions found, try the device itself
            echo "/dev/$dev_name"
            return 0
        fi
    done

    return 1
}

# Detect filesystem type
detect_filesystem() {
    device="$1"

    if command -v blkid >/dev/null 2>&1; then
        # Use blkid to get filesystem type
        # Note: On some systems blkid might not work without root, so we try it anyway
        fstype=$($SUDO_CMD blkid -s TYPE -o value "$device" 2>/dev/null | head -n1)
        if [ -n "$fstype" ] && [ "$fstype" != "$device"* ]; then
            echo "$fstype"
            return 0
        fi
    fi

    # Default to vfat if detection fails
    echo "vfat"
    return 0
}

# Mount USB stick
mount_usb_stick() {
    device="$1"

    # Check if already mounted
    if mount | grep -q "$USB_MOUNT_POINT"; then
        echo "$USB_MOUNT_POINT"
        return 0
    fi

    # Create mount point if needed
    if [ ! -d "$USB_MOUNT_POINT" ]; then
        if ! $SUDO_CMD mkdir -p "$USB_MOUNT_POINT" 2>/dev/null; then
            return 1
        fi
    fi

    # Detect filesystem type
    fstype=$(detect_filesystem "$device")

    # Try to mount with detected filesystem type
    if $SUDO_CMD mount -t "$fstype" "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        USB_MOUNTED_BY_SCRIPT=1
        echo "$USB_MOUNT_POINT"
        return 0
    else
        # Try auto-detection
        if $SUDO_CMD mount "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
            USB_MOUNTED_BY_SCRIPT=1
            echo "$USB_MOUNT_POINT"
            return 0
        fi
    fi

    return 1
}

# Unmount USB stick
unmount_usb_stick() {
    if [ -d "$USB_MOUNT_POINT" ] && mount | grep -q "$USB_MOUNT_POINT"; then
        # Sync before unmount
        sync

        if $SUDO_CMD umount "$USB_MOUNT_POINT" 2>/dev/null; then
            return 0
        fi
    fi
    return 0
}

# Main script
main() {
    print_info "Collecting logs..."
    sleep 1

    # Check if log file list exists
    if [ ! -f "$LOG_FILE_LIST" ]; then
        print_error "Error: log-file-list.txt"
        print_error "not found"
        print_info ""
        return 1
    fi

    # Detect USB stick
    usb_device=""
    if ! usb_device=$(detect_usb_stick); then
        print_error "Connect USBStick"
        print_info ""
        print_info ""
        return 1
    fi

    # Mount USB stick
    mount_point=""
    if ! mount_point=$(mount_usb_stick "$usb_device"); then
        print_error "Failed to mount USB"
        print_info ""
        print_info ""
        return 1
    fi

    # Create log folder with timestamp
    timestamp=$(date +%Y-%m-%d-%H%M%S)
    log_folder="$mount_point/micropanel-logs-$timestamp"

    if ! $SUDO_CMD mkdir -p "$log_folder" 2>/dev/null; then
        print_error "Error: USB full or"
        print_error "write protected"
        print_info ""
        unmount_usb_stick
        return 1
    fi

    # Copy log files from list
    copied_count=0
    total_count=0

    while IFS= read -r log_file || [ -n "$log_file" ]; do
        # Skip empty lines
        [ -z "$log_file" ] && continue

        # Skip comments (lines starting with #)
        case "$log_file" in
            \#*) continue ;;
        esac

        # Trim whitespace
        log_file=$(echo "$log_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip if empty after trim
        [ -z "$log_file" ] && continue

        total_count=$((total_count + 1))

        # Check if file exists
        if [ -f "$log_file" ]; then
            # Copy file (overwrite if exists)
            if $SUDO_CMD cp -f "$log_file" "$log_folder/" 2>/dev/null; then
                copied_count=$((copied_count + 1))
            fi
        # Check if directory exists
        elif [ -d "$log_file" ]; then
            # Get directory name for destination
            dir_name=$(basename "$log_file")
            # Copy directory recursively (overwrite if exists)
            if $SUDO_CMD cp -rf "$log_file" "$log_folder/$dir_name" 2>/dev/null; then
                copied_count=$((copied_count + 1))
            fi
        fi
    done < "$LOG_FILE_LIST"

    # Ensure all data is flushed to USB
    sync

    # Unmount USB stick so user can safely remove it
    unmount_usb_stick

    # Show success message
    print_success "Logs transferred!"
    print_info "Copied $copied_count/$total_count files"
    print_info "SafeToRemove USB"

    return 0
}

# Run main function
main
exit $?
