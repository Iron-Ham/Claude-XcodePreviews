#!/bin/bash
#
# preview-spm.sh - Build and capture SwiftUI previews from SPM packages
#
# Creates a temporary Xcode project that depends on the local SPM package,
# builds a minimal preview host app, and captures a screenshot.
#
# Usage:
#   preview-spm.sh <swift-file> [options]
#
# Options:
#   --package <path>      Path to Package.swift (auto-detected from file)
#   --module <name>       Module name (auto-detected from path)
#   --simulator <name>    Simulator (default: iPhone 17 Pro)
#   --output <path>       Output screenshot path
#   --keep                Keep temporary project after capture
#   --verbose             Show detailed output
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Parse arguments
SWIFT_FILE=""
PACKAGE_PATH=""
MODULE=""
SIMULATOR="iPhone 17 Pro"
OUTPUT="/tmp/preview-spm.png"
KEEP="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --package) PACKAGE_PATH="$2"; shift 2 ;;
        --module) MODULE="$2"; shift 2 ;;
        --simulator) SIMULATOR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --keep) KEEP="true"; shift ;;
        --verbose) VERBOSE="true"; shift ;;
        --help|-h) head -18 "$0" | tail -16; exit 0 ;;
        -*) log_error "Unknown option: $1"; exit 1 ;;
        *)
            if [[ -n "$1" && -z "$SWIFT_FILE" ]]; then
                SWIFT_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Validation
if [[ -z "$SWIFT_FILE" ]]; then
    log_error "No Swift file specified"
    exit 1
fi

if [[ ! -f "$SWIFT_FILE" ]]; then
    log_error "File not found: $SWIFT_FILE"
    exit 1
fi

SWIFT_FILE="$(cd "$(dirname "$SWIFT_FILE")" && pwd)/$(basename "$SWIFT_FILE")"
FILENAME=$(basename "$SWIFT_FILE" .swift)

# Find Package.swift
if [[ -z "$PACKAGE_PATH" ]]; then
    DIR=$(dirname "$SWIFT_FILE")
    while [[ "$DIR" != "/" ]]; do
        if [[ -f "$DIR/Package.swift" ]]; then
            PACKAGE_PATH="$DIR/Package.swift"
            break
        fi
        DIR=$(dirname "$DIR")
    done
fi

if [[ -z "$PACKAGE_PATH" || ! -f "$PACKAGE_PATH" ]]; then
    log_error "Could not find Package.swift"
    exit 1
fi

PACKAGE_DIR=$(dirname "$PACKAGE_PATH")
PACKAGE_NAME=$(grep "name:" "$PACKAGE_PATH" | head -1 | sed 's/.*name:[[:space:]]*"\([^"]*\)".*/\1/')

log_info "Preview: $FILENAME"
log_info "Package: $PACKAGE_NAME ($PACKAGE_DIR)"

# Auto-detect module from file path (Sources/ModuleName/...)
if [[ -z "$MODULE" ]]; then
    RELATIVE="${SWIFT_FILE#$PACKAGE_DIR/}"
    if [[ "$RELATIVE" =~ Sources/([^/]+)/ ]]; then
        MODULE="${BASH_REMATCH[1]}"
    fi
fi

if [[ -z "$MODULE" ]]; then
    log_error "Could not detect module. Use --module <name>"
    exit 1
fi

log_info "Module: $MODULE"

# Extract deployment target from Package.swift
IOS_DEPLOYMENT=$(grep -E "\.iOS\(\.v[0-9]+" "$PACKAGE_PATH" | head -1 | sed 's/.*\.v\([0-9]*\).*/\1/' || echo "17")
log_info "iOS Deployment Target: $IOS_DEPLOYMENT.0"

# Extract imports from the file
IMPORTS=$(grep "^import " "$SWIFT_FILE" | sed 's/import //' | sort -u)
log_info "Imports: $(echo $IMPORTS | tr '\n' ' ')"

# Check for xcodeproj gem
if ! ruby -r xcodeproj -e "" 2>/dev/null; then
    export GEM_HOME="$HOME/.gem/ruby/2.6.0"
    export PATH="$GEM_HOME/bin:$PATH"
    if ! ruby -r xcodeproj -e "" 2>/dev/null; then
        log_error "xcodeproj gem not found"
        log_info "Install with: gem install xcodeproj --user-install"
        exit 1
    fi
fi

# Find simulator
SIM_UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    if 'iOS' in runtime:
        for device in devices:
            if device['name'] == '$SIMULATOR' and device['isAvailable']:
                print(device['udid'])
                sys.exit(0)
sys.exit(1)
" 2>/dev/null)

if [[ -z "$SIM_UDID" ]]; then
    log_error "Simulator not found: $SIMULATOR"
    exit 1
fi

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

# Extract preview body
PREVIEW_BODY=$(python3 << PYEOF
import re
import sys

with open("$SWIFT_FILE", "r") as f:
    content = f.read()

# Find first #Preview and extract its body using brace counting
preview_match = re.search(r'#Preview(?:\s*\([^)]*\))?\s*\{', content)
if not preview_match:
    print("Text(\"No #Preview found\")")
    sys.exit(0)

start = preview_match.end()
brace_count = 1
pos = start

while pos < len(content) and brace_count > 0:
    char = content[pos]
    if char == '{':
        brace_count += 1
    elif char == '}':
        brace_count -= 1
    pos += 1

if brace_count != 0:
    print("Text(\"Malformed #Preview\")")
    sys.exit(0)

body = content[start:pos-1]

lines = body.split('\n')
while lines and not lines[0].strip():
    lines.pop(0)
while lines and not lines[-1].strip():
    lines.pop()

if lines:
    min_indent = float('inf')
    for line in lines:
        if line.strip():
            indent = len(line) - len(line.lstrip())
            min_indent = min(min_indent, indent)
    if min_indent < float('inf') and min_indent > 0:
        lines = [line[min_indent:] if len(line) >= min_indent else line for line in lines]
    body = '\n'.join(lines)
else:
    body = ""

print(body)
PYEOF
)

# Create temporary project directory
TEMP_DIR="/tmp/preview-spm-project-$$"
mkdir -p "$TEMP_DIR/PreviewHost"

log_info "Creating temporary Xcode project..."

# Generate import statements
IMPORT_STATEMENTS="import SwiftUI
import $MODULE"

for imp in $IMPORTS; do
    if [[ "$imp" != "SwiftUI" && "$imp" != "$MODULE" ]]; then
        IMPORT_STATEMENTS="$IMPORT_STATEMENTS
import $imp"
    fi
done

# Indent preview body
INDENTED_BODY=$(echo "$PREVIEW_BODY" | sed 's/^/            /')

# Create the preview host app
cat > "$TEMP_DIR/PreviewHost/PreviewHostApp.swift" << SWIFT_EOF
// Auto-generated PreviewHost for $FILENAME

$IMPORT_STATEMENTS

@main
struct PreviewHostApp: App {
    var body: some Scene {
        WindowGroup {
            PreviewContent()
        }
    }
}

struct PreviewContent: View {
    var body: some View {
$INDENTED_BODY
    }
}
SWIFT_EOF

if [[ "$VERBOSE" == "true" ]]; then
    echo "--- Generated PreviewHostApp.swift ---"
    cat "$TEMP_DIR/PreviewHost/PreviewHostApp.swift"
    echo "--- End ---"
fi

# Create Xcode project using xcodeproj gem
log_info "Creating Xcode project with SPM dependency..."

export TEMP_DIR PACKAGE_DIR PACKAGE_NAME MODULE IOS_DEPLOYMENT

ruby << 'RUBY_SCRIPT'
require 'xcodeproj'
require 'fileutils'

temp_dir = ENV['TEMP_DIR']
package_dir = ENV['PACKAGE_DIR']
package_name = ENV['PACKAGE_NAME']
module_name = ENV['MODULE']
ios_deployment = ENV['IOS_DEPLOYMENT'] || '17'

project_path = File.join(temp_dir, 'PreviewHost.xcodeproj')

# Create new project
project = Xcodeproj::Project.new(project_path)

# Create main group
main_group = project.main_group
preview_group = main_group.new_group('PreviewHost', File.join(temp_dir, 'PreviewHost'))

# Add source file
source_file = File.join(temp_dir, 'PreviewHost', 'PreviewHostApp.swift')
file_ref = preview_group.new_file(source_file)

# Create app target with correct deployment target
target = project.new_target(:application, 'PreviewHost', :ios, "#{ios_deployment}.0")

# Add source to target
target.source_build_phase.add_file_reference(file_ref)

# Configure build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.preview.spm.host'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = "#{ios_deployment}.0"
end

# Add local SPM package reference
# Note: xcodeproj doesn't have great SPM support, so we'll add it via xcodebuild

project.save

puts "Created Xcode project: #{project_path}"

# Create scheme
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project_path, 'PreviewHost')
puts "Created scheme: PreviewHost"
RUBY_SCRIPT

# Add SPM package using xcodebuild (xcodeproj doesn't handle SPM well)
log_info "Adding SPM package dependency..."

# Create workspace that includes both the project and the package
mkdir -p "$TEMP_DIR/PreviewHost.xcworkspace"
cat > "$TEMP_DIR/PreviewHost.xcworkspace/contents.xcworkspacedata" << WORKSPACE_EOF
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:PreviewHost.xcodeproj">
   </FileRef>
   <FileRef
      location = "absolute:$PACKAGE_DIR">
   </FileRef>
</Workspace>
WORKSPACE_EOF

# Now we need to add the package dependency to the project
# This requires modifying the project.pbxproj to add XCRemoteSwiftPackageReference

log_info "Configuring package dependency..."

ruby << RUBY_SCRIPT
require 'xcodeproj'

temp_dir = ENV['TEMP_DIR']
package_dir = ENV['PACKAGE_DIR']
package_name = ENV['PACKAGE_NAME']
module_name = ENV['MODULE']

project_path = File.join(temp_dir, 'PreviewHost.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Add local package reference
# XCLocalSwiftPackageReference
pkg_ref = project.root_object.project_references || []

# Create XCLocalSwiftPackageReference manually in the project
# This is a bit hacky but xcodeproj doesn't have native support

# Get the target
target = project.targets.find { |t| t.name == 'PreviewHost' }

# For local packages, we need to add them differently
# Create a package reference
local_pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
local_pkg.relative_path = package_dir

# Add to root object
project.root_object.package_references ||= []
project.root_object.package_references << local_pkg

# Create product dependency
pkg_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
pkg_product.product_name = module_name
pkg_product.package = local_pkg

# Add to target's package product dependencies
target.package_product_dependencies ||= []
target.package_product_dependencies << pkg_product

# Add to frameworks build phase
# The product dependency should automatically be linked

project.save
puts "Added local package dependency: #{package_name} -> #{module_name}"
RUBY_SCRIPT

if [[ $? -ne 0 ]]; then
    log_warning "Could not add package via xcodeproj, trying alternative method..."
fi

# Build
log_info "Building preview..."

BUILD_CMD="xcodebuild build"
BUILD_CMD="$BUILD_CMD -project \"$TEMP_DIR/PreviewHost.xcodeproj\""
BUILD_CMD="$BUILD_CMD -scheme PreviewHost"
BUILD_CMD="$BUILD_CMD -destination \"platform=iOS Simulator,id=$SIM_UDID\""
BUILD_CMD="$BUILD_CMD -derivedDataPath \"$TEMP_DIR/DerivedData\""
BUILD_CMD="$BUILD_CMD -packageCachePath \"$TEMP_DIR/PackageCache\""

if [[ "$VERBOSE" == "true" ]]; then
    eval $BUILD_CMD 2>&1
else
    eval $BUILD_CMD 2>&1 | tail -30
fi

BUILD_EXIT=${PIPESTATUS[0]}

if [[ $BUILD_EXIT -ne 0 ]]; then
    log_error "Build failed"
    if [[ "$KEEP" != "true" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    exit 1
fi

log_success "Build completed"

# Find the built app
APP_PATH=$(find "$TEMP_DIR/DerivedData" -name "PreviewHost.app" -type d 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
    log_error "Could not find built app"
    if [[ "$KEEP" != "true" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    exit 1
fi

log_info "Installing and launching..."

# Terminate any existing instance
xcrun simctl terminate "$SIM_UDID" "com.preview.spm.host" 2>/dev/null || true

# Install and launch
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# Open Simulator
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"
sleep 1

# Launch the app
xcrun simctl launch "$SIM_UDID" "com.preview.spm.host" 2>&1 || true
sleep 3

# Try to bring to foreground
xcrun simctl launch "$SIM_UDID" "com.preview.spm.host" 2>&1 || true
sleep 1

log_info "Capturing screenshot..."
mkdir -p "$(dirname "$OUTPUT")"
xcrun simctl io "$SIM_UDID" screenshot "$OUTPUT"

# Terminate app
xcrun simctl terminate "$SIM_UDID" "com.preview.spm.host" 2>/dev/null || true

# Cleanup
if [[ "$KEEP" != "true" ]]; then
    rm -rf "$TEMP_DIR"
else
    log_info "Temporary project kept at: $TEMP_DIR"
fi

if [[ -f "$OUTPUT" ]]; then
    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    log_success "Preview captured: $OUTPUT ($SIZE)"
    echo ""
    echo "PREVIEW_PATH=$OUTPUT"
else
    log_error "Failed to capture screenshot"
    exit 1
fi
