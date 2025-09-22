#!/bin/bash

# Network Data Info Script for MicroPanel TextBoxScreen
# Shows RX/TX bytes and dropped packets for specified interface
# Usage: ./network-data-info.sh --interface=eth0

# Parse command line arguments
INTERFACE=""
for arg in "$@"; do
    case $arg in
        --interface=*)
            INTERFACE="${arg#*=}"
            shift
            ;;
        *)
            echo "Usage: $0 --interface=<interface_name>"
            exit 1
            ;;
    esac
done

# Check if interface parameter provided
if [ -z "$INTERFACE" ]; then
    echo "Error: No interface"
    echo "Usage: --interface=X"
    exit 1
fi

# Function to convert bytes to human readable format (using shell arithmetic)
format_bytes() {
    local bytes=$1

    if [ "$bytes" -ge 1073741824 ]; then
        # GB - divide by 1024^3
        local gb=$((bytes / 1073741824))
        local remainder=$((bytes % 1073741824))
        local decimal=$((remainder * 10 / 1073741824))
        if [ "$decimal" -eq 0 ]; then
            echo "${gb}GB"
        else
            echo "${gb}.${decimal}GB"
        fi
    elif [ "$bytes" -ge 1048576 ]; then
        # MB - divide by 1024^2
        local mb=$((bytes / 1048576))
        local remainder=$((bytes % 1048576))
        local decimal=$((remainder * 10 / 1048576))
        if [ "$decimal" -eq 0 ]; then
            echo "${mb}MB"
        else
            echo "${mb}.${decimal}MB"
        fi
    elif [ "$bytes" -ge 1024 ]; then
        # KB - divide by 1024
        local kb=$((bytes / 1024))
        local remainder=$((bytes % 1024))
        local decimal=$((remainder * 10 / 1024))
        if [ "$decimal" -eq 0 ]; then
            echo "${kb}KB"
        else
            echo "${kb}.${decimal}KB"
        fi
    else
        # Bytes
        echo "${bytes}B"
    fi
}

# Read interface stats from /proc/net/dev
# Format: interface: rx_bytes rx_packets rx_errs rx_drop ... tx_bytes tx_packets tx_errs tx_drop ...
stats=$(awk -v iface="$INTERFACE:" '$1 == iface {print $2, $4, $10, $12}' /proc/net/dev)

if [ -z "$stats" ]; then
    echo "Interface not found"
    echo "$INTERFACE"
    echo "Check name"
    exit 1
fi

# Parse stats: rx_bytes rx_drop tx_bytes tx_drop
read rx_bytes rx_drop tx_bytes tx_drop <<< "$stats"

# Format bytes to human readable
rx_formatted=$(format_bytes $rx_bytes)
tx_formatted=$(format_bytes $tx_bytes)

# Calculate total dropped packets
total_dropped=$((rx_drop + tx_drop))

# Output in the required format for OLED display (16 chars max per line)
echo "RxBytes:$rx_formatted"
echo "TxBytes:$tx_formatted"
echo "Dropped:$total_dropped"