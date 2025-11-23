#!/bin/sh

# List available patterns for pattern-generator app
# Updates pattern-list.txt if pattern-generator is running and list changed
# Usage: ./list-pattern.sh --launcher=127.0.0.1:8081 --pattern-generator=127.0.0.1:8082

MICROPANEL_HOME="${MICROPANEL_HOME:-/home/pi/micropanel}"

# Detect buildroot vs Pi OS environment for pattern-list.txt path
if [ -f "/usr/share/micropanel/configs/pattern-list.txt" ] || [ -d "/usr/share/micropanel" ]; then
    # Buildroot: system-wide install to /usr/share/micropanel/configs/
    PATTERN_LIST_FILE="/usr/share/micropanel/configs/pattern-list.txt"
elif [ -f "$MICROPANEL_HOME/usr/share/micropanel/configs/pattern-list.txt" ]; then
    # Pi OS: development install to $MICROPANEL_HOME/usr/share/micropanel/configs/
    PATTERN_LIST_FILE="$MICROPANEL_HOME/usr/share/micropanel/configs/pattern-list.txt"
else
    # Fallback: legacy location for backward compatibility
    PATTERN_LIST_FILE="$MICROPANEL_HOME/configs/pattern-list.txt"
fi

# Default values
LAUNCHER_ADDR="127.0.0.1:8081"
PATTERN_GEN_ADDR="127.0.0.1:8082"
TIMEOUT=2

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --launcher=*)
            LAUNCHER_ADDR="${arg#*=}"
            ;;
        --pattern-generator=*)
            PATTERN_GEN_ADDR="${arg#*=}"
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
else
    # Fallback: try PATH
    LAUNCHER_CLIENT="launcher-client"
fi

# Check if pattern-generator is running by querying for current pattern
check_pattern_generator_running() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$PATTERN_GEN_ADDR" --command=get-pattern --timeoutsec="$TIMEOUT" 2>&1)

    # If we get a valid response (not empty, not error), app is running
    if [ $? -eq 0 ] && [ -n "$response" ] && ! echo "$response" | grep -qi "error"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Start pattern-generator app via launcher
start_pattern_generator() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$LAUNCHER_ADDR" --command=start-app --command-arg=pattern-generator --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && echo "$response" | grep -q "OK"; then
        # Wait for app to start (give it 2 seconds)
        sleep 2
        return 0
    else
        return 1
    fi
}

# Query live pattern list from pattern-generator
query_live_patterns() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$PATTERN_GEN_ADDR" --command=list-patterns --timeoutsec="$TIMEOUT" 2>&1)

    if [ -n "$response" ] && ! echo "$response" | grep -qi "error"; then
        # Convert comma-separated list to newline-separated
        echo "$response" | tr ',' '\n'
        return 0
    else
        return 1
    fi
}

# Update pattern-list.txt if live list differs from file
update_pattern_list_if_changed() {
    local live_patterns="$1"
    local current_patterns

    # Read current patterns from file (skip comments and empty lines)
    current_patterns=$(grep -v '^#' "$PATTERN_LIST_FILE" 2>/dev/null | grep -v '^[[:space:]]*$')

    # Compare (sort both for consistent comparison)
    local live_sorted=$(echo "$live_patterns" | sort)
    local current_sorted=$(echo "$current_patterns" | sort)

    if [ "$live_sorted" != "$current_sorted" ]; then
        # Lists differ - update file
        {
            echo "# Pattern Generator - Pattern List"
            echo "# Auto-updated from live pattern-generator app"
            echo "# $(date)"
            echo ""
            echo "$live_patterns"
        } > "$PATTERN_LIST_FILE"
        return 0  # Updated
    else
        return 1  # No change
    fi
}

# Get current active pattern from pattern-generator
get_current_pattern() {
    local response
    response=$("$LAUNCHER_CLIENT" --srv="$PATTERN_GEN_ADDR" --command=get-pattern --timeoutsec="$TIMEOUT" 2>&1)

    if [ $? -eq 0 ] && [ -n "$response" ] && ! echo "$response" | grep -qi "error"; then
        echo "$response"
        return 0
    else
        # No pattern running or app not available
        return 1
    fi
}

# Create minimal pattern list file if missing
create_minimal_pattern_list() {
    # Create configs directory if needed
    mkdir -p "$(dirname "$PATTERN_LIST_FILE")"

    # Create minimal pattern list with common colors
    cat > "$PATTERN_LIST_FILE" << 'EOF'
# Pattern Generator - Default Pattern List
# Format: One pattern name per line
# This file is auto-updated when pattern-generator app is queried

# Basic colors (most commonly used)
white
black
red
green
blue
cyan
magenta
yellow

# Test patterns
grayscale-ramp
colorbar
ansi-checker
zone-boundary-grid
blooming-detection
cross-dimming
EOF
}

# Main logic
main() {
    # Check if pattern list file exists, create if missing
    if [ ! -f "$PATTERN_LIST_FILE" ]; then
        create_minimal_pattern_list
    fi

    # Try to update pattern list from live app (ONLY if already running - don't auto-start!)
    if check_pattern_generator_running; then
        # App is running - query live patterns
        live_patterns=$(query_live_patterns)
        if [ $? -eq 0 ] && [ -n "$live_patterns" ]; then
            # Successfully got live patterns - update file if changed
            update_pattern_list_if_changed "$live_patterns" >/dev/null 2>&1
        fi
    fi
    # If app not running, just use the static file - DO NOT auto-start!

    # Output pattern list with "off" first and "grayscale-ramp" second (default startup pattern)
    echo "off"
    echo "grayscale-ramp"
    grep -v '^#' "$PATTERN_LIST_FILE" | grep -v '^[[:space:]]*$' | grep -v '^grayscale-ramp$'

    # Note: GenericListScreen will call this script again for list_selection
    # to get the current pattern. Since we can't distinguish the calls,
    # we rely on GenericListScreen to parse the output and query for current pattern separately.
}

# Run main function
main
exit 0
