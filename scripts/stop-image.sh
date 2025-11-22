#!/bin/sh

# Stop touch-gallery app via launcher
# Usage: ./stop-image.sh --launcher=127.0.0.1:8081

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default values
LAUNCHER_ADDR="127.0.0.1:8081"
TIMEOUT=2

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --launcher=*)
            LAUNCHER_ADDR="${arg#*=}"
            ;;
        *)
            # Ignore unknown arguments
            ;;
    esac
done

# Auto-detect launcher-client binary location
if [ -n "$LAUNCHER_CLIENT" ] && [ -x "$LAUNCHER_CLIENT" ]; then
    # User explicitly set LAUNCHER_CLIENT - use it
    true
elif [ -x "/usr/bin/launcher-client" ]; then
    # Buildroot: installed to /usr/bin/
    LAUNCHER_CLIENT="/usr/bin/launcher-client"
elif [ -n "$MICROPANEL_HOME" ] && [ -x "$MICROPANEL_HOME/build/launcher-client" ]; then
    # Pi OS: development build
    LAUNCHER_CLIENT="$MICROPANEL_HOME/build/launcher-client"
elif [ -n "$MICROPANEL_HOME" ] && [ -x "$MICROPANEL_HOME/usr/bin/launcher-client" ]; then
    # Pi OS: installed to usr/bin
    LAUNCHER_CLIENT="$MICROPANEL_HOME/usr/bin/launcher-client"
else
    # Fallback: try PATH
    LAUNCHER_CLIENT="launcher-client"
fi

echo "Stopping image playback"

# Stop touch-gallery via launcher
response=$("$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=stop-app --command-arg=gallery --timeoutsec="$TIMEOUT" 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
    if echo "$response" | grep -q "OK"; then
        echo "Touch-gallery stopped successfully"
        exit 0
    elif echo "$response" | grep -q "no-app-running"; then
        echo "Touch-gallery already stopped"
        exit 0
    fi
fi

# If we get here, something went wrong
echo "Error stopping touch-gallery: $response"
exit 1
