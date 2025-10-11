#!/bin/sh
# Script to detect SSD1306 (0x3C) on I2C bus for Raspberry Pi

I2C_BUS=""
DEFAULT_BUS="/dev/i2c-3"

# Check if running on Raspberry Pi
if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    # Try to detect SSD1306 at 0x3C on i2c-1 or i2c-3
    for bus in /dev/i2c-1 /dev/i2c-2 /dev/i2c-3; do
        if [ -e "$bus" ]; then
            bus_num=$(echo "$bus" | sed 's|/dev/i2c-||')
            # Use i2cdetect to scan for device at 0x3C
            if i2cdetect -y "$bus_num" 2>/dev/null | grep -q " 3c "; then
                I2C_BUS="$bus"
                echo "Detected SSD1306 at 0x3C on $bus" >&2
                break
            fi
        fi
    done
fi

# Fallback to default if not detected
if [ -z "$I2C_BUS" ]; then
    I2C_BUS="$DEFAULT_BUS"
    echo "Using default I2C bus: $DEFAULT_BUS" >&2
fi

# Output the bus to stdout
echo "$I2C_BUS"
