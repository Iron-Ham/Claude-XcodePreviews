#!/bin/bash
#
# sim-interact.sh - Simulator interaction utilities
#
# Usage:
#   sim-interact.sh tap <x> <y>           Tap at coordinates (requires cliclick)
#   sim-interact.sh type <text>           Type text into focused field
#   sim-interact.sh paste <text>          Paste text via clipboard
#   sim-interact.sh screenshot [output]   Take a screenshot
#   sim-interact.sh launch <bundle-id>    Launch an app
#   sim-interact.sh home                  Go to home screen
#
# Note: Some features require additional tools or accessibility permissions.

set -e

SIMULATOR="booted"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

ACTION="${1:-help}"
shift || true

case $ACTION in
    tap)
        X="$1"
        Y="$2"
        if [[ -z "$X" || -z "$Y" ]]; then
            log_error "Usage: sim-interact.sh tap <x> <y>"
            exit 1
        fi

        # Check for cliclick
        if command -v cliclick &>/dev/null; then
            log_info "Using cliclick to tap at ($X, $Y)"
            # Get Simulator window position and calculate absolute coords
            # This requires the Simulator window to be visible
            osascript -e '
            tell application "Simulator" to activate
            delay 0.5
            ' 2>/dev/null || true
            cliclick "c:$X,$Y"
            log_success "Tapped at ($X, $Y)"
        else
            log_warning "cliclick not installed. Install with: brew install cliclick"
            log_info "Alternative: Use Accessibility permissions with AppleScript"
            log_info "Or manually interact with the Simulator"
            exit 1
        fi
        ;;

    type)
        TEXT="$1"
        if [[ -z "$TEXT" ]]; then
            log_error "Usage: sim-interact.sh type <text>"
            exit 1
        fi

        # Try using keyboard input simulation
        if command -v cliclick &>/dev/null; then
            log_info "Typing: $TEXT"
            osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
            sleep 0.3
            cliclick "t:$TEXT"
            log_success "Typed text"
        else
            log_warning "cliclick not installed for keyboard input"
            log_info "Falling back to clipboard paste method..."
            echo -n "$TEXT" | xcrun simctl pbcopy "$SIMULATOR"
            log_info "Text copied to simulator clipboard. Manually paste with Cmd+V in Simulator."
        fi
        ;;

    paste)
        TEXT="$1"
        if [[ -z "$TEXT" ]]; then
            log_error "Usage: sim-interact.sh paste <text>"
            exit 1
        fi

        log_info "Copying to simulator clipboard: $TEXT"
        echo -n "$TEXT" | xcrun simctl pbcopy "$SIMULATOR"
        log_success "Text copied to simulator clipboard"
        log_info "Trigger paste with Cmd+V in Simulator, or use 'sim-interact.sh type' with cliclick"
        ;;

    screenshot)
        OUTPUT="${1:-/tmp/sim-screenshot.png}"
        log_info "Capturing screenshot..."
        xcrun simctl io "$SIMULATOR" screenshot "$OUTPUT"
        if [[ -f "$OUTPUT" ]]; then
            SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
            log_success "Screenshot saved: $OUTPUT ($SIZE)"
            echo "SCREENSHOT_PATH=$OUTPUT"
        else
            log_error "Failed to capture screenshot"
            exit 1
        fi
        ;;

    launch)
        BUNDLE_ID="$1"
        if [[ -z "$BUNDLE_ID" ]]; then
            log_error "Usage: sim-interact.sh launch <bundle-id>"
            exit 1
        fi
        log_info "Launching: $BUNDLE_ID"
        xcrun simctl launch "$SIMULATOR" "$BUNDLE_ID"
        log_success "App launched"
        ;;

    home)
        log_info "Pressing home button..."
        xcrun simctl spawn "$SIMULATOR" notifyutil -p com.apple.springboard.simulatorHomePressed 2>/dev/null || {
            # Alternative method
            xcrun simctl ui "$SIMULATOR" appearance 2>/dev/null || log_warning "Could not press home"
        }
        ;;

    url)
        URL="$1"
        if [[ -z "$URL" ]]; then
            log_error "Usage: sim-interact.sh url <url>"
            exit 1
        fi
        log_info "Opening URL: $URL"
        xcrun simctl openurl "$SIMULATOR" "$URL"
        log_success "URL opened"
        ;;

    help|--help|-h)
        cat << 'EOF'
Simulator Interaction Utilities

USAGE:
    sim-interact.sh <action> [arguments]

ACTIONS:
    tap <x> <y>         Tap at screen coordinates (requires cliclick)
    type <text>         Type text into focused field (requires cliclick)
    paste <text>        Copy text to simulator clipboard
    screenshot [path]   Capture screenshot (default: /tmp/sim-screenshot.png)
    launch <bundle-id>  Launch an app by bundle identifier
    home                Press home button
    url <url>           Open a URL in the simulator

REQUIREMENTS:
    - For tap/type: Install cliclick with `brew install cliclick`
    - For AppleScript UI automation: Grant accessibility permissions

EXAMPLES:
    sim-interact.sh screenshot ~/Desktop/preview.png
    sim-interact.sh launch com.apple.mobilesafari
    sim-interact.sh paste "search query"
    sim-interact.sh tap 200 400

EOF
        ;;

    *)
        log_error "Unknown action: $ACTION"
        echo "Use 'sim-interact.sh help' for usage information"
        exit 1
        ;;
esac
