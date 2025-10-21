#!/bin/sh

# Network Interfaces List Script for MicroPanel GenericListScreen
# Lists available network interfaces for stats monitoring
# Compatible with /bin/sh (POSIX) - works on buildroot busybox and Raspberry Pi OS

# Read /proc/net/dev and extract interface names
# Skip header lines (first 2 lines) and loopback interface
interfaces=$(awk 'NR > 2 && $1 != "lo:" {
    # Remove colon from interface name
    gsub(":", "", $1)
    print $1
}' /proc/net/dev | sort)

# Output format for GenericListScreen:
# Each line represents a menu item
for interface in $interfaces; do
    echo "$interface"
done
