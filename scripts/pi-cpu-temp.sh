#!/bin/bash

# Pi CPU Temperature Script for MicroPanel
# Outputs formatted CPU temperature and frequency information

# Get CPU temperature (in millidegrees Celsius)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    temp_celsius=$((temp_raw / 1000))
    temp_fahrenheit=$(((temp_celsius * 9 / 5) + 32))
else
    temp_celsius="N/A"
    temp_fahrenheit="N/A"
fi

# Get CPU frequency (in Hz, convert to MHz)
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    freq_raw=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)
    freq_mhz=$((freq_raw / 1000))
else
    freq_mhz="N/A"
fi

# Get CPU usage (1 second average)
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
if [ -z "$cpu_usage" ]; then
    cpu_usage="N/A"
else
    cpu_usage=$(printf "%.1f" "$cpu_usage")
fi

# Output formatted information (4 lines max for MicroPanel)
echo "Temp: ${temp_celsius}°C"
echo "Freq: ${freq_mhz}MHz"
echo "Usage: ${cpu_usage}%"
echo "$(date '+%H:%M:%S')"