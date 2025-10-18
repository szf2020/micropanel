#!/bin/sh

# Collect logs to USB stick
# Copies log files listed in log-file-list.txt to USB stick
# Compatible with /bin/sh

# USB stick configuration
USB_MOUNT_POINT="/tmp/micropanel-usb"
USB_MOUNTED_BY_SCRIPT=0

# Paths
MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"
LOG_FILE_LIST="$MICROPANEL_HOME/configs/log-file-list.txt"

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

        local dev_name=$(basename "$block_dev")
        local removable=$(cat "$block_dev/removable" 2>/dev/null || echo "0")

        # Check if it's removable (USB sticks have removable=1)
        if [ "$removable" = "1" ]; then
            # Found a removable device, check for partitions
            for part in "$block_dev"/"$dev_name"*; do
                if [ -e "$part" ]; then
                    local part_name=$(basename "$part")
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
    local device="$1"

    if command -v blkid >/dev/null 2>&1; then
        local fstype=$(sudo blkid -o value -s TYPE "$device" 2>/dev/null)
        if [ -n "$fstype" ]; then
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
    local device="$1"

    # Check if already mounted
    if mount | grep -q "$USB_MOUNT_POINT"; then
        echo "$USB_MOUNT_POINT"
        return 0
    fi

    # Create mount point if needed
    if [ ! -d "$USB_MOUNT_POINT" ]; then
        if ! sudo mkdir -p "$USB_MOUNT_POINT" 2>/dev/null; then
            return 1
        fi
    fi

    # Detect filesystem type
    local fstype=$(detect_filesystem "$device")

    # Try to mount with detected filesystem type
    if sudo mount -t "$fstype" "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        USB_MOUNTED_BY_SCRIPT=1
        echo "$USB_MOUNT_POINT"
        return 0
    else
        # Try auto-detection
        if sudo mount "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
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

        if sudo umount "$USB_MOUNT_POINT" 2>/dev/null; then
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
    local usb_device
    if ! usb_device=$(detect_usb_stick); then
        print_error "Connect USBStick"
        print_info ""
        print_info ""
        return 1
    fi

    # Mount USB stick
    local mount_point
    if ! mount_point=$(mount_usb_stick "$usb_device"); then
        print_error "Failed to mount USB"
        print_info ""
        print_info ""
        return 1
    fi

    # Create log folder with timestamp
    local timestamp=$(date +%Y-%m-%d-%H%M%S)
    local log_folder="$mount_point/micropanel-logs-$timestamp"

    if ! sudo mkdir -p "$log_folder" 2>/dev/null; then
        print_error "Error: USB full or"
        print_error "write protected"
        print_info ""
        unmount_usb_stick
        return 1
    fi

    # Copy log files from list
    local copied_count=0
    local total_count=0

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
            if sudo cp -f "$log_file" "$log_folder/" 2>/dev/null; then
                copied_count=$((copied_count + 1))
            fi
        # Check if directory exists
        elif [ -d "$log_file" ]; then
            # Get directory name for destination
            local dir_name=$(basename "$log_file")
            # Copy directory recursively (overwrite if exists)
            if sudo cp -rf "$log_file" "$log_folder/$dir_name" 2>/dev/null; then
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
