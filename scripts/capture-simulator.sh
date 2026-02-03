#!/bin/bash
#
# capture-simulator.sh - Capture a screenshot from the current simulator state
#
# Usage: capture-simulator.sh [options]
#
# Options:
#   --simulator <name|udid>  Simulator to capture from (default: booted)
#   --output <path>          Output image path (default: /tmp/simulator-screenshot.png)
#   --type <format>          Image format: png, tiff, bmp, gif, jpeg (default: png)
#   --wait <seconds>         Wait before capturing (default: 0)
#
# Examples:
#   capture-simulator.sh
#   capture-simulator.sh --output ~/Desktop/screenshot.png
#   capture-simulator.sh --simulator "iPhone 17 Pro" --wait 2

set -e

# Default values
SIMULATOR="booted"
OUTPUT_PATH="/tmp/simulator-screenshot.png"
IMAGE_TYPE="png"
WAIT_TIME=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --simulator)
            SIMULATOR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --type)
            IMAGE_TYPE="$2"
            shift 2
            ;;
        --wait)
            WAIT_TIME="$2"
            shift 2
            ;;
        --help|-h)
            head -20 "$0" | tail -18
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find simulator UDID if name given
find_simulator_udid() {
    local identifier="$1"

    # Check if it's already a UDID (UUID format)
    if [[ "$identifier" =~ ^[A-F0-9]{8}-([A-F0-9]{4}-){3}[A-F0-9]{12}$ ]]; then
        echo "$identifier"
        return 0
    fi

    # Special case for "booted"
    if [[ "$identifier" == "booted" ]]; then
        echo "booted"
        return 0
    fi

    # Find by name
    xcrun simctl list devices available -j | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime:
        for device in devices:
            if device['name'] == '$identifier' and device['isAvailable']:
                print(device['udid'])
                sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

# Get simulator info
get_simulator_info() {
    local udid="$1"
    if [[ "$udid" == "booted" ]]; then
        xcrun simctl list devices booted -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for device in devices:
        if device['state'] == 'Booted':
            print(f\"{device['name']} ({device['udid']})\")
            sys.exit(0)
print('No booted simulator')
" 2>/dev/null
    else
        xcrun simctl list devices -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for device in devices:
        if device['udid'] == '$udid':
            print(f\"{device['name']} ({device['state']})\")
            sys.exit(0)
" 2>/dev/null
    fi
}

# Main
main() {
    # Resolve simulator
    if [[ "$SIMULATOR" != "booted" ]]; then
        SIMULATOR=$(find_simulator_udid "$SIMULATOR")
        if [[ -z "$SIMULATOR" ]]; then
            log_error "Could not find simulator"
            exit 1
        fi
    fi

    # Check if any simulator is booted
    BOOTED_COUNT=$(xcrun simctl list devices booted | grep -c "Booted" || echo "0")
    if [[ "$BOOTED_COUNT" -eq 0 ]]; then
        log_error "No simulator is currently booted"
        log_info "Boot a simulator with: xcrun simctl boot <device-name>"
        log_info "Available devices:"
        xcrun simctl list devices available | grep -E "iPhone|iPad" | head -5
        exit 1
    fi

    SIM_INFO=$(get_simulator_info "$SIMULATOR")
    log_info "Capturing from: $SIM_INFO"

    # Wait if requested
    if [[ "$WAIT_TIME" -gt 0 ]]; then
        log_info "Waiting ${WAIT_TIME}s..."
        sleep "$WAIT_TIME"
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT_PATH")"

    # Capture screenshot
    log_info "Capturing screenshot..."
    xcrun simctl io "$SIMULATOR" screenshot --type="$IMAGE_TYPE" "$OUTPUT_PATH"

    if [[ -f "$OUTPUT_PATH" ]]; then
        FILE_SIZE=$(ls -lh "$OUTPUT_PATH" | awk '{print $5}')
        log_success "Screenshot saved: $OUTPUT_PATH ($FILE_SIZE)"
        echo ""
        echo "SCREENSHOT_PATH=$OUTPUT_PATH"
    else
        log_error "Failed to capture screenshot"
        exit 1
    fi
}

main
