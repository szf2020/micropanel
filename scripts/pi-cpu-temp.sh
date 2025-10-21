#!/bin/sh

# Pi CPU Temperature Script for MicroPanel
# Outputs formatted CPU temperature and frequency information
# Compatible with /bin/sh (POSIX) - works on buildroot busybox and Raspberry Pi OS

# Get CPU temperature (in millidegrees Celsius)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp_celsius=$((temp_raw / 1000))
else
    temp_celsius="N/A"
fi

# Get CPU frequency (in Hz, convert to MHz)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    freq_raw=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    freq_mhz=$((freq_raw / 1000))
else
    freq_mhz="N/A"
fi

# Get CPU usage - simplified approach compatible with busybox
# Try method 1: Read from /proc/stat (most portable)
if [ -f /proc/stat ]; then
    # Read initial CPU stats
    cpu_line1=$(grep '^cpu ' /proc/stat)
    sleep 1
    # Read CPU stats after 1 second
    cpu_line2=$(grep '^cpu ' /proc/stat)

    # Parse values (user, nice, system, idle, iowait, irq, softirq)
    set -- $cpu_line1
    idle1=$5
    total1=0
    shift  # Remove 'cpu' label
    for val in "$@"; do
        total1=$((total1 + val))
    done

    set -- $cpu_line2
    idle2=$5
    total2=0
    shift
    for val in "$@"; do
        total2=$((total2 + val))
    done

    # Calculate usage
    idle_delta=$((idle2 - idle1))
    total_delta=$((total2 - total1))

    if [ "$total_delta" -gt 0 ]; then
        # Calculate percentage: (total - idle) / total * 100
        usage=$((100 * (total_delta - idle_delta) / total_delta))
        cpu_usage="${usage}.0"
    else
        cpu_usage="N/A"
    fi
else
    cpu_usage="N/A"
fi

# Output formatted information (4 lines max for MicroPanel)
# Note: Degree symbol (°) converted to asterisk (*) for ASCII compatibility
echo "Temp: ${temp_celsius}*C"
echo "Freq: ${freq_mhz}MHz"
echo "Usage: ${cpu_usage}%"
echo "$(date '+%H:%M:%S')"
