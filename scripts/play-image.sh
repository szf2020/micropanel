#!/bin/sh

# Play a specific image using touch-gallery app
# Usage: ./play-image.sh --image=photo.jpg --launcher=127.0.0.1:8081 --touch-gallery=127.0.0.1:8086

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Default values
LAUNCHER_ADDR="127.0.0.1:8081"
GALLERY_ADDR="127.0.0.1:8086"
IMAGE_NAME=""
IMAGE_DIR=""
TIMEOUT=10

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --image=*)
            IMAGE_NAME="${arg#*=}"
            ;;
        --image-dir=*)
            IMAGE_DIR="${arg#*=}"
            ;;
        --launcher=*)
            LAUNCHER_ADDR="${arg#*=}"
            ;;
        --touch-gallery=*)
            GALLERY_ADDR="${arg#*=}"
            ;;
        *)
            # Ignore unknown arguments
            ;;
    esac
done

# Validate required arguments
if [ -z "$IMAGE_NAME" ]; then
    echo "Error: --image required"
    exit 1
fi

# Auto-detect launcher-client binary location (MUST come before usage!)
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

# Check if touch-gallery is running
check_gallery_running() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$GALLERY_ADDR" --command=get-image --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && ! echo "$response" | grep -qi "error"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Start touch-gallery app via launcher
start_gallery() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=start-app --command-arg=gallery --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && echo "$response" | grep -q "OK"; then
        # Wait for app to start
        sleep 2
        return 0
    else
        return 1
    fi
}

# Send display command to touch-gallery
send_display_command() {
    local image="$1"
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$GALLERY_ADDR" --command=display --command-arg="$image" --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && echo "$response" | grep -q "OK"; then
        echo "Image '$image' displayed"
        return 0
    else
        echo "Error: Display command failed - $response"
        return 1
    fi
}

# Main logic
main() {
    # Handle "off" - stop the gallery entirely
    if [ "$IMAGE_NAME" = "off" ]; then
        # Stop touch-gallery via launcher
        response=$("$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=stop-app --timeoutsec="$TIMEOUT" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            if echo "$response" | grep -q "OK"; then
                echo "Touch-gallery stopped (off)"
                exit 0
            elif echo "$response" | grep -q "no-app-running"; then
                echo "Touch-gallery already stopped (off)"
                exit 0
            fi
        fi

        # If we get here, something went wrong
        echo "Error stopping touch-gallery: $response"
        exit 1
    fi

    # Check if touch-gallery is running
    if ! check_gallery_running; then
        # Not running - stop any current app and start touch-gallery
        echo "Starting touch-gallery..."

        # Stop any currently running app to free up launcher slot
        "$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=stop-app --timeoutsec="$TIMEOUT" >/dev/null 2>&1
        sleep 0.5  # Brief delay for cleanup

        if ! start_gallery; then
            echo "Error: Failed to start touch-gallery"
            echo "Check app-launcher"
            exit 1
        fi
    else
        # App is running - small delay to avoid connection race condition
        sleep 0.1
    fi

    # If directory specified, set it first
    if [ -n "$IMAGE_DIR" ]; then
        response=$("$LAUNCHER_CLIENT" --srv="$GALLERY_ADDR" --command=set-directory --command-arg="$IMAGE_DIR" --timeoutsec="$TIMEOUT" 2>&1)
        if [ $? -ne 0 ] || ! echo "$response" | grep -q "OK"; then
            echo "Warning: Failed to set directory to $IMAGE_DIR"
            # Continue anyway - image might be in current directory
        fi
    fi

    # Send display command
    if send_display_command "$IMAGE_NAME"; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main
