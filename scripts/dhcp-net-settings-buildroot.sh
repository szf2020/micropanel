#!/bin/sh
# dhcp-net-settings-buildroot.sh - Buildroot specific network configuration
# This script is called from the main dhcp-net-settings.sh script

# Check for required environment variables
if [ -z "$INTERFACE" ]; then
    echo "[ERROR] INTERFACE environment variable not set"
    echo "RESULT:ERROR"
    exit 1
fi

# Function to output messages when verbose mode is enabled
log_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[INFO] $1"
    fi
}

# Function to output error messages and exit
error_exit() {
    echo "[ERROR] $1"
    echo "RESULT:ERROR"
    exit 1
}

# Function to clean IP addresses (remove leading zeros)
clean_ip() {
    echo "$1" | awk -F. '{printf "%d.%d.%d.%d", $1, $2, $3, $4}'
}

# Define variables
INTERFACES_FILE="/etc/network/interfaces"
RESOLV_CONF="/etc/resolv.conf"

# Backup current settings
if [ "$DRY_RUN" -eq 0 ]; then
    if [ -f "$INTERFACES_FILE" ]; then
        cp "$INTERFACES_FILE" "$BACKUP_PATH/interfaces.$(date +%Y%m%d%H%M%S)" || \
            error_exit "Failed to backup interfaces file"
    fi

    if [ -f "$RESOLV_CONF" ]; then
        cp "$RESOLV_CONF" "$BACKUP_PATH/resolv.conf.$(date +%Y%m%d%H%M%S)" || \
            log_verbose "Failed to backup resolv.conf (not critical)"
    fi
else
    log_verbose "[DRY-RUN] Would backup network configuration files"
fi

# Get current settings
if [ -z "$MODE" ]; then
    # Check interfaces file first
    if [ -f "$INTERFACES_FILE" ] && grep -q "iface $INTERFACE" "$INTERFACES_FILE" 2>/dev/null; then
        if grep -q "iface $INTERFACE inet dhcp" "$INTERFACES_FILE" 2>/dev/null; then
            echo "mode=dhcp"
        else
            echo "mode=static"
            # Extract IP information
            IP=$(grep -A10 "iface $INTERFACE inet static" "$INTERFACES_FILE" 2>/dev/null | grep -o "address.*" | cut -d' ' -f2)
            GATEWAY=$(grep -A10 "iface $INTERFACE inet static" "$INTERFACES_FILE" 2>/dev/null | grep -o "gateway.*" | cut -d' ' -f2)
            NETMASK=$(grep -A10 "iface $INTERFACE inet static" "$INTERFACES_FILE" 2>/dev/null | grep -o "netmask.*" | cut -d' ' -f2)

            echo "ip=$IP"
            echo "gateway=$GATEWAY"
            echo "netmask=$NETMASK"

            # Extract DNS information from resolv.conf
            if [ -f "$RESOLV_CONF" ]; then
                DNS1=$(grep "nameserver" "$RESOLV_CONF" | head -1 | awk '{print $2}')
                DNS2=$(grep "nameserver" "$RESOLV_CONF" | head -2 | tail -1 | awk '{print $2}')
                DNS3=$(grep "nameserver" "$RESOLV_CONF" | head -3 | tail -1 | awk '{print $2}')

                [ -n "$DNS1" ] && echo "dns1=$DNS1"
                [ -n "$DNS2" ] && echo "dns2=$DNS2"
                [ -n "$DNS3" ] && echo "dns3=$DNS3"
            fi
        fi
    else
        # Check actual network interface state as fallback
        CURRENT_IP=$(ip -4 addr show dev "$INTERFACE" 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2)

        if [ -n "$CURRENT_IP" ]; then
            # Check for DHCP configuration using multiple methods
            DHCP_DETECTED=0

            # Method 1: Traditional udhcpc process check
            if ps aux | grep -q "[u]dhcpc.*$INTERFACE" || [ -f "/var/run/udhcpc.$INTERFACE.pid" ]; then
                DHCP_DETECTED=1
                log_verbose "DHCP detected: udhcpc process found"
            fi

            # Method 2: systemd-networkd DHCP check
            if [ "$DHCP_DETECTED" -eq 0 ] && command -v networkctl >/dev/null 2>&1; then
                # Check if systemd-networkd is managing this interface with DHCP
                if networkctl status "$INTERFACE" 2>/dev/null | grep -q "DHCP4.*yes"; then
                    DHCP_DETECTED=1
                    log_verbose "DHCP detected: systemd-networkd DHCP4 enabled"
                fi
            fi

            # Method 3: Check systemd-networkd config files
            if [ "$DHCP_DETECTED" -eq 0 ] && [ -d "/etc/systemd/network" ]; then
                for config in /etc/systemd/network/*.network; do
                    if [ -f "$config" ] && grep -q "Name=$INTERFACE" "$config" 2>/dev/null; then
                        if grep -q "DHCP=.*yes\|DHCP=true\|DHCP4=.*yes\|DHCP4=true" "$config" 2>/dev/null; then
                            DHCP_DETECTED=1
                            log_verbose "DHCP detected: systemd-networkd config file $config"
                            break
                        fi
                    fi
                done
            fi

            if [ "$DHCP_DETECTED" -eq 1 ]; then
                echo "mode=dhcp"
            else
                # Assuming static if no DHCP configuration found
                echo "mode=static"
                echo "ip=$CURRENT_IP"

                # Get gateway
                GATEWAY=$(ip route | grep "default.*$INTERFACE" | head -1 | cut -d' ' -f3)
                [ -n "$GATEWAY" ] && echo "gateway=$GATEWAY"

                # Get netmask (might be in CIDR format)
                CIDR=$(ip -4 addr show dev "$INTERFACE" | grep -o 'inet [0-9.]*\/[0-9]*' | cut -d'/' -f2)
                if [ -n "$CIDR" ]; then
                    # Convert CIDR to netmask (simplified)
                    case "$CIDR" in
                        8) NETMASK="255.0.0.0" ;;
                        16) NETMASK="255.255.0.0" ;;
                        24) NETMASK="255.255.255.0" ;;
                        *)  NETMASK="255.255.255.0" ;; # Default
                    esac
                    echo "netmask=$NETMASK"
                fi

                # Get DNS from resolv.conf
                if [ -f "$RESOLV_CONF" ]; then
                    DNS1=$(grep "nameserver" "$RESOLV_CONF" | head -1 | awk '{print $2}')
                    DNS2=$(grep "nameserver" "$RESOLV_CONF" | head -2 | tail -1 | awk '{print $2}')
                    DNS3=$(grep "nameserver" "$RESOLV_CONF" | head -3 | tail -1 | awk '{print $2}')

                    [ -n "$DNS1" ] && echo "dns1=$DNS1"
                    [ -n "$DNS2" ] && echo "dns2=$DNS2"
                    [ -n "$DNS3" ] && echo "dns3=$DNS3"
                fi
            fi
        else
            # No IP configured, assume DHCP is intended
            echo "mode=dhcp"
        fi
    fi

    echo "RESULT:OK"
    exit 0
fi

# Set new settings
if [ "$MODE" = "dhcp" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        # Check if systemd-networkd is active
        if systemctl is-active systemd-networkd >/dev/null 2>&1; then
            log_verbose "Using systemd-networkd configuration"

            # Create systemd-networkd config directory if it doesn't exist
            mkdir -p /etc/systemd/network

            # Create network configuration file for this interface
            NETWORK_CONFIG="/etc/systemd/network/50-$INTERFACE.network"
            cat > "$NETWORK_CONFIG" << EOF
[Match]
Name=$INTERFACE

[Network]
DHCP=yes
EOF
            log_verbose "Created systemd-networkd config: $NETWORK_CONFIG"

            # Restart systemd-networkd to apply changes
            systemctl restart systemd-networkd
            log_verbose "Restarted systemd-networkd service"
        else
            # Fallback to traditional interfaces file method
            log_verbose "Using traditional interfaces file method"

            # First ensure interfaces file exists
            touch "$INTERFACES_FILE"

            # Remove any existing configuration for this interface
            sed -i "/iface $INTERFACE inet/,/^[^[:space:]]/d" "$INTERFACES_FILE"

            # Add new DHCP configuration
            echo "" >> "$INTERFACES_FILE"
            echo "auto $INTERFACE" >> "$INTERFACES_FILE"
            echo "iface $INTERFACE inet dhcp" >> "$INTERFACES_FILE"

            # Restart networking
            # Try different methods for different buildroot configurations
            if [ -f /etc/init.d/S40network ]; then
                /etc/init.d/S40network restart
            elif [ -f /etc/init.d/network ]; then
                /etc/init.d/network restart
            elif [ -x /sbin/ifdown ] && [ -x /sbin/ifup ]; then
                ifdown "$INTERFACE" 2>/dev/null
                ifup "$INTERFACE"
            else
                # Direct interface management as last resort
                ip link set "$INTERFACE" down
                ip link set "$INTERFACE" up
                udhcpc -i "$INTERFACE" -n
            fi
        fi
    else
        log_verbose "[DRY-RUN] Would configure $INTERFACE for DHCP"
        if systemctl is-active systemd-networkd >/dev/null 2>&1; then
            log_verbose "[DRY-RUN] Would create systemd-networkd config file"
            log_verbose "[DRY-RUN] Would restart systemd-networkd service"
        else
            log_verbose "[DRY-RUN] Would configure in interfaces file"
            log_verbose "[DRY-RUN] Would restart networking service"
        fi
    fi
elif [ "$MODE" = "static" ]; then
    if [ -z "$IP" ] || [ -z "$GATEWAY" ] || [ -z "$NETMASK" ]; then
        error_exit "Static mode requires IP, gateway, and netmask parameters"
    fi

    # Clean IP addresses to remove leading zeros
    CLEAN_IP=$(clean_ip "$IP")
    CLEAN_GATEWAY=$(clean_ip "$GATEWAY")
    
    # Clean DNS addresses if provided
    if [ -n "$DNS1" ]; then
        CLEAN_DNS1=$(clean_ip "$DNS1")
    fi
    if [ -n "$DNS2" ]; then
        CLEAN_DNS2=$(clean_ip "$DNS2")
    fi
    if [ -n "$DNS3" ]; then
        CLEAN_DNS3=$(clean_ip "$DNS3")
    fi

    log_verbose "Cleaned IP address: $CLEAN_IP (was $IP)"
    log_verbose "Cleaned Gateway: $CLEAN_GATEWAY (was $GATEWAY)"
    [ -n "$DNS1" ] && log_verbose "Cleaned DNS1: $CLEAN_DNS1 (was $DNS1)"
    [ -n "$DNS2" ] && log_verbose "Cleaned DNS2: $CLEAN_DNS2 (was $DNS2)"
    [ -n "$DNS3" ] && log_verbose "Cleaned DNS3: $CLEAN_DNS3 (was $DNS3)"

    # Convert netmask to CIDR for direct IP configuration
    CIDR=24  # Default to /24 if we can't calculate
    case "$NETMASK" in
        255.0.0.0) CIDR=8 ;;
        255.255.0.0) CIDR=16 ;;
        255.255.255.0) CIDR=24 ;;
    esac

    if [ "$DRY_RUN" -eq 0 ]; then
        # Check if systemd-networkd is active
        if systemctl is-active systemd-networkd >/dev/null 2>&1; then
            log_verbose "Using systemd-networkd configuration"

            # Create systemd-networkd config directory if it doesn't exist
            mkdir -p /etc/systemd/network

            # Create network configuration file for this interface
            NETWORK_CONFIG="/etc/systemd/network/50-$INTERFACE.network"
            cat > "$NETWORK_CONFIG" << EOF
[Match]
Name=$INTERFACE

[Network]
DHCP=no
Address=$CLEAN_IP/$CIDR
Gateway=$CLEAN_GATEWAY
EOF

            # Add DNS configuration if provided
            if [ -n "$DNS1" ] || [ -n "$DNS2" ] || [ -n "$DNS3" ]; then
                echo "" >> "$NETWORK_CONFIG"
                [ -n "$DNS1" ] && echo "DNS=$CLEAN_DNS1" >> "$NETWORK_CONFIG"
                [ -n "$DNS2" ] && echo "DNS=$CLEAN_DNS2" >> "$NETWORK_CONFIG"
                [ -n "$DNS3" ] && echo "DNS=$CLEAN_DNS3" >> "$NETWORK_CONFIG"
            fi

            log_verbose "Created systemd-networkd config: $NETWORK_CONFIG"

            # Restart systemd-networkd to apply changes
            systemctl restart systemd-networkd
            log_verbose "Restarted systemd-networkd service"
        else
            # Fallback to traditional interfaces file method
            log_verbose "Using traditional interfaces file method"

            # First ensure interfaces file exists
            touch "$INTERFACES_FILE"

            # Remove any existing configuration for this interface
            sed -i "/iface $INTERFACE inet/,/^[^[:space:]]/d" "$INTERFACES_FILE"

            # Add new static configuration
            echo "" >> "$INTERFACES_FILE"
            echo "auto $INTERFACE" >> "$INTERFACES_FILE"
            echo "iface $INTERFACE inet static" >> "$INTERFACES_FILE"
            echo "    address $CLEAN_IP" >> "$INTERFACES_FILE"
            echo "    netmask $NETMASK" >> "$INTERFACES_FILE"
            echo "    gateway $CLEAN_GATEWAY" >> "$INTERFACES_FILE"

            # Update resolv.conf for DNS if provided
            if [ -n "$DNS1" ] || [ -n "$DNS2" ] || [ -n "$DNS3" ]; then
                # Write new resolv.conf
                : > "$RESOLV_CONF"  # Clear file
                [ -n "$DNS1" ] && echo "nameserver $CLEAN_DNS1" >> "$RESOLV_CONF"
                [ -n "$DNS2" ] && echo "nameserver $CLEAN_DNS2" >> "$RESOLV_CONF"
                [ -n "$DNS3" ] && echo "nameserver $CLEAN_DNS3" >> "$RESOLV_CONF"
            fi

            # Restart networking
            # Try different methods for different buildroot configurations
            if [ -f /etc/init.d/S40network ]; then
                /etc/init.d/S40network restart
            elif [ -f /etc/init.d/network ]; then
                /etc/init.d/network restart
            elif [ -x /sbin/ifdown ] && [ -x /sbin/ifup ]; then
                ifdown "$INTERFACE" 2>/dev/null
                ifup "$INTERFACE"
            else
                # Direct interface management as last resort
                ip link set "$INTERFACE" down
                ip addr flush dev "$INTERFACE"
                ip addr add "$CLEAN_IP/$CIDR" dev "$INTERFACE"
                ip link set "$INTERFACE" up
                ip route add default via "$CLEAN_GATEWAY" dev "$INTERFACE"
            fi
        fi
    else
        log_verbose "[DRY-RUN] Would configure $INTERFACE for static IP"
        if systemctl is-active systemd-networkd >/dev/null 2>&1; then
            log_verbose "[DRY-RUN] Would create systemd-networkd config file"
            log_verbose "[DRY-RUN] Would restart systemd-networkd service"
        else
            log_verbose "[DRY-RUN] Would configure in interfaces file"
            log_verbose "[DRY-RUN] Would restart networking service"
        fi
        log_verbose "[DRY-RUN]   IP: $CLEAN_IP"
        log_verbose "[DRY-RUN]   Gateway: $CLEAN_GATEWAY"
        log_verbose "[DRY-RUN]   Netmask: $NETMASK"
        [ -n "$DNS1" ] && log_verbose "[DRY-RUN]   DNS1: $CLEAN_DNS1"
        [ -n "$DNS2" ] && log_verbose "[DRY-RUN]   DNS2: $CLEAN_DNS2"
        [ -n "$DNS3" ] && log_verbose "[DRY-RUN]   DNS3: $CLEAN_DNS3"
    fi
else
    error_exit "Invalid mode: $MODE. Must be 'dhcp' or 'static'"
fi

echo "RESULT:OK"
exit 0
