#!/bin/bash
#
# preview-dynamic.sh - Dynamically create and build a preview target
#
# Creates a PreviewHost app target in an existing Xcode project that:
# 1. Depends on the module containing the view
# 2. Uses the #Preview content as its entry point
# 3. Builds only what's needed (much faster than full app)
#
# Works with both static modules and frameworks.
#
# Usage:
#   preview-dynamic.sh <swift-file> --project <path> [options]
#   preview-dynamic.sh <swift-file> --workspace <path> [options]
#
# Options:
#   --project <path>      Xcode project file
#   --workspace <path>    Xcode workspace file
#   --target <name>       Module containing the file (auto-detected)
#   --simulator <name>    Simulator (default: iPhone 17 Pro)
#   --output <path>       Output screenshot path
#   --keep                Keep the preview target after capture
#   --verbose             Show detailed output

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
PROJECT=""
WORKSPACE=""
TARGET=""
SIMULATOR="iPhone 17 Pro"
OUTPUT="/tmp/preview-dynamic.png"
KEEP="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --project) PROJECT="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --target) TARGET="$2"; shift 2 ;;
        --simulator) SIMULATOR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --keep) KEEP="true"; shift ;;
        --verbose) VERBOSE="true"; shift ;;
        --help|-h) head -20 "$0" | tail -18; exit 0 ;;
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

if [[ -z "$PROJECT" && -z "$WORKSPACE" ]]; then
    log_error "Must specify --project or --workspace"
    exit 1
fi

SWIFT_FILE="$(cd "$(dirname "$SWIFT_FILE")" && pwd)/$(basename "$SWIFT_FILE")"
FILENAME=$(basename "$SWIFT_FILE" .swift)

# Find project path
if [[ -n "$WORKSPACE" ]]; then
    WORKSPACE="$(cd "$(dirname "$WORKSPACE")" && pwd)/$(basename "$WORKSPACE")"
    PROJECT_PATH=$(find "$(dirname "$WORKSPACE")" -maxdepth 1 -name "*.xcodeproj" -type d | head -1)
else
    PROJECT_PATH="$(cd "$(dirname "$PROJECT")" && pwd)/$(basename "$PROJECT")"
fi

PROJECT_DIR=$(dirname "$PROJECT_PATH")

log_info "Preview: $FILENAME"
log_info "Project: $PROJECT_PATH"

# Extract imports
IMPORTS=$(grep "^import " "$SWIFT_FILE" | sed 's/import //' | sort -u)
log_info "Imports: $(echo $IMPORTS | tr '\n' ' ')"

# Auto-detect target from file path
if [[ -z "$TARGET" ]]; then
    RELATIVE="${SWIFT_FILE#$PROJECT_DIR/}"
    if [[ "$RELATIVE" =~ Modules/([^/]+)/ ]]; then
        TARGET="${BASH_REMATCH[1]}"
    elif [[ "$RELATIVE" =~ Sources/([^/]+)/ ]]; then
        TARGET="${BASH_REMATCH[1]}"
    fi
    [[ -n "$TARGET" ]] && log_info "Auto-detected target: $TARGET"
fi

# Find simulator
SIM_UDID=$("$SCRIPT_DIR/preview-helper.rb" find-simulator "$SIMULATOR" 2>/dev/null)

if [[ -z "$SIM_UDID" ]]; then
    log_error "Simulator not found: $SIMULATOR"
    exit 1
fi

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

# Check for xcodeproj gem
if ! ruby -r xcodeproj -e "" 2>/dev/null; then
    # Try with user gem path
    export GEM_HOME="$HOME/.gem/ruby/2.6.0"
    export PATH="$GEM_HOME/bin:$PATH"
    if ! ruby -r xcodeproj -e "" 2>/dev/null; then
        log_error "xcodeproj gem not found"
        log_info "Install with: gem install xcodeproj --user-install"
        exit 1
    fi
fi

# Create preview directory
PREVIEW_DIR="$PROJECT_DIR/PreviewHost"
mkdir -p "$PREVIEW_DIR"

# Extract preview body using Ruby helper
PREVIEW_BODY=$("$SCRIPT_DIR/preview-helper.rb" extract-preview "$SWIFT_FILE")

# Generate imports - include the target module if detected
IMPORT_STATEMENTS=""
for imp in $IMPORTS; do
    IMPORT_STATEMENTS="${IMPORT_STATEMENTS}import $imp
"
done

# Add the target module if it's not already in imports (the source file is PART OF the module)
if [[ -n "$TARGET" ]] && ! echo "$IMPORTS" | grep -q "^$TARGET$"; then
    IMPORT_STATEMENTS="${IMPORT_STATEMENTS}import $TARGET
"
    log_info "Added import for target module: $TARGET"
fi

# Indent preview body for proper Swift formatting
INDENTED_BODY=$(echo "$PREVIEW_BODY" | sed 's/^/            /')

# Generate preview host app
cat > "$PREVIEW_DIR/PreviewHostApp.swift" << SWIFT_EOF
// Auto-generated PreviewHost for $FILENAME

import SwiftUI
${IMPORT_STATEMENTS}
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
${INDENTED_BODY}
    }
}
SWIFT_EOF

log_info "Generated preview host"

if [[ "$VERBOSE" == "true" ]]; then
    echo "--- Generated PreviewHostApp.swift ---"
    cat "$PREVIEW_DIR/PreviewHostApp.swift"
    echo "--- End ---"
fi

# Inject target using xcodeproj
log_info "Injecting PreviewHost target..."

export PROJECT_PATH TARGET PREVIEW_DIR IMPORTS

export SWIFT_FILE_ABS="$SWIFT_FILE"

ruby << 'RUBY_SCRIPT'
require 'xcodeproj'
require 'set'

project_path = ENV['PROJECT_PATH']
target_name = ENV['TARGET']
preview_dir = ENV['PREVIEW_DIR']
imports = ENV['IMPORTS'].to_s.split
swift_file = ENV['SWIFT_FILE_ABS']

project = Xcodeproj::Project.open(project_path)

# Remove existing PreviewHost
existing = project.targets.find { |t| t.name == 'PreviewHost' }
if existing
  puts "Removing existing PreviewHost..."
  # Remove the file group too, not just the target
  project.main_group.groups.each do |g|
    if g.name == 'PreviewHost'
      g.remove_from_project
      break
    end
  end
  existing.remove_from_project
end

# ---------------------------------------------------------------
# Detect which app target the Swift file belongs to
# ---------------------------------------------------------------
app_target = nil
project.targets.each do |t|
  next unless t.product_type == 'com.apple.product-type.application'
  t.source_build_phase.files_references.each do |ref|
    next unless ref.respond_to?(:real_path)
    if ref.real_path.to_s == swift_file
      app_target = t
      break
    end
  end
  break if app_target
end

# Fallback: match by directory convention (e.g., AnyClaw/Features/...)
if app_target.nil?
  project_dir = File.dirname(project_path)
  relative = swift_file.sub("#{project_dir}/", '')
  first_dir = relative.split('/').first

  app_target = project.targets.find do |t|
    t.product_type == 'com.apple.product-type.application' && t.name == first_dir
  end
end

if app_target
  puts "Detected app target: #{app_target.name}"
end

# ---------------------------------------------------------------
# Find framework/library dependency targets for imports
# ---------------------------------------------------------------
dep_targets = []
imports.each do |imp|
  target = project.targets.find { |t| t.name == imp }
  dep_targets << target if target
end

if target_name && !dep_targets.any? { |t| t.name == target_name }
  main_target = project.targets.find { |t| t.name == target_name }
  dep_targets << main_target if main_target
end

puts "Dependencies: #{dep_targets.map(&:name).join(', ')}"

# Get deployment target from first dependency or app target
deployment_target = '17.0'
ref_target = dep_targets.first || app_target
ref_target&.build_configurations&.each do |config|
  if dt = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
    deployment_target = dt
    break
  end
end
puts "Deployment target: iOS #{deployment_target}"

# ---------------------------------------------------------------
# Create PreviewHost target
# ---------------------------------------------------------------
puts "Creating PreviewHost target..."
preview_target = project.new_target(:application, 'PreviewHost', :ios, deployment_target)

preview_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = 'PreviewHost'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.preview.host'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
end

# ---------------------------------------------------------------
# Add PreviewHost source files
# ---------------------------------------------------------------
preview_group = project.main_group.new_group('PreviewHost', preview_dir)
Dir.glob(File.join(preview_dir, '*.swift')).each do |f|
  ref = preview_group.new_file(f)
  preview_target.source_build_phase.add_file_reference(ref)
  puts "  Added source: #{File.basename(f)}"
end

# ---------------------------------------------------------------
# When the Swift file lives in the app target (not a separately
# importable module), add it directly so its types are available
# to the generated PreviewHostApp.swift.
#
# We intentionally only include this one file rather than every
# source in the app target — bulk-inclusion would balloon compile
# times and likely introduce unrelated build errors.  If the view
# references sibling types that aren't in a module, users should
# either extract shared types into a module or add the missing
# files to PreviewHost manually via --keep and Xcode.
# ---------------------------------------------------------------
is_app_target_file = app_target &&
  (target_name.nil? || target_name.empty? || target_name == app_target.name)

if is_app_target_file
  file_ref = project.new_file(swift_file)
  preview_target.source_build_phase.add_file_reference(file_ref)
  puts "  Added app-target source: #{File.basename(swift_file)}"
  STDERR.puts "NOTE: #{File.basename(swift_file)} belongs to app target '#{app_target.name}', not a separate module."
  STDERR.puts "      Only this file is included — sibling types from the app target won't be available."
end

# ---------------------------------------------------------------
# Add target dependencies + link/embed products
# ---------------------------------------------------------------
# For each dependency we need TWO things:
#   1. A target dependency (ensures correct build order)
#   2. Linking/embedding of the product:
#      - Static libraries  → link into the binary
#      - Dynamic frameworks → link AND embed (copy into .app/Frameworks)
#
# Without the "Embed Frameworks" phase, dynamic frameworks would
# link at build time but crash at launch with "image not found".
embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Frameworks'
embed_phase.symbol_dst_subfolder_spec = :frameworks
preview_target.build_phases << embed_phase

dep_targets.each do |dep|
  # 1. Target dependency — ensures this module builds before PreviewHost
  preview_target.add_dependency(dep)
  puts "  Added dependency: #{dep.name}"

  # 2. Link (and embed, for frameworks) the built product
  if dep.product_type == 'com.apple.product-type.library.static'
    preview_target.frameworks_build_phase.add_file_reference(dep.product_reference)
    puts "  Linked static library: #{dep.name}"
  elsif dep.product_type == 'com.apple.product-type.framework'
    build_file = embed_phase.add_file_reference(dep.product_reference)
    build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
    puts "  Embedded framework: #{dep.name}"
  end
end

# ---------------------------------------------------------------
# Forward SPM package product dependencies
# ---------------------------------------------------------------
# Modules often depend on SPM packages (e.g. Firebase, Alamofire).
# Those dependencies live on the original target as
# XCSwiftPackageProductDependency objects pointing at a shared
# XCRemoteSwiftPackageReference.  We create new dependency objects
# for PreviewHost that reference the same package — this lets
# Xcode resolve and link them without duplicating the package.
# Deduplication by product_name prevents double-linking.
all_pkg_deps = Set.new

# 1. From framework/library dependency targets
dep_targets.each do |dep|
  dep.package_product_dependencies.each do |pkg_dep|
    next if all_pkg_deps.include?(pkg_dep.product_name)
    all_pkg_deps << pkg_dep.product_name

    new_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    new_dep.product_name = pkg_dep.product_name
    new_dep.package = pkg_dep.package
    preview_target.package_product_dependencies << new_dep
  end
end

unless all_pkg_deps.empty?
  puts "  Added #{all_pkg_deps.size} SPM package dependencies: #{all_pkg_deps.to_a.join(', ')}"
end

# 2. From the app target (may have packages not used by the modules)
if app_target
  app_target.package_product_dependencies.each do |pkg_dep|
    next if all_pkg_deps.include?(pkg_dep.product_name)
    all_pkg_deps << pkg_dep.product_name

    new_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    new_dep.product_name = pkg_dep.product_name
    new_dep.package = pkg_dep.package
    preview_target.package_product_dependencies << new_dep
  end
end

# ---------------------------------------------------------------
# Find and add resource bundle targets
# ---------------------------------------------------------------
# Many modules ship a companion .bundle target for assets, colors,
# localisations, etc.  Naming conventions vary:
#   - Tuist:    ProjectName_ModuleName
#   - Generic:  ModuleName_Resources / ModuleNameResources
#   - Direct:   ModuleName (when the bundle IS the target)
#
# We walk the full transitive dependency graph so nested module
# resources are also picked up.
project_name = File.basename(project_path, '.xcodeproj')
bundle_targets = []
all_dep_names = Set.new

# Collect all dependency names recursively (BFS to avoid recursion
# inside a heredoc where `def` is unavailable)
queue = dep_targets.dup
while !queue.empty?
  t = queue.shift
  next if t.nil?
  next if all_dep_names.include?(t.name)
  all_dep_names << t.name
  t.dependencies.each do |dep_ref|
    queue << dep_ref.target if dep_ref.target
  end
end

# Match bundle targets against known naming patterns
project.targets.each do |t|
  next unless t.product_type == 'com.apple.product-type.bundle'
  all_dep_names.each do |dep_name|
    patterns = [
      "#{project_name}_#{dep_name}",  # Tuist convention
      "#{dep_name}_Resources",         # Generic _Resources suffix
      "#{dep_name}Resources",          # Generic Resources suffix
      dep_name                         # Direct match
    ]
    if patterns.any? { |p| t.name == p }
      bundle_targets << t unless bundle_targets.include?(t)
      break
    end
  end
end

# Add bundles as dependencies and copy their products into the app
if !bundle_targets.empty?
  puts "Resource bundles: #{bundle_targets.map(&:name).join(', ')}"
  copy_phase = preview_target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
  bundle_targets.each do |bundle|
    preview_target.add_dependency(bundle)
    if bundle.product_reference && copy_phase
      copy_phase.add_file_reference(bundle.product_reference)
      puts "  Copying bundle: #{bundle.name}"
    end
  end
end

project.save
puts "Project saved"

# Create scheme
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(preview_target)
scheme.set_launch_target(preview_target)
scheme.save_as(project_path, 'PreviewHost')
puts "Created scheme: PreviewHost"
RUBY_SCRIPT

RUBY_EXIT=$?
if [[ $RUBY_EXIT -ne 0 ]]; then
    log_error "Failed to inject target"
    exit 1
fi

log_success "Target injected"

# Build
log_info "Building PreviewHost..."

BUILD_CMD="xcodebuild build"
if [[ -n "$WORKSPACE" ]]; then
    BUILD_CMD="$BUILD_CMD -workspace \"$WORKSPACE\""
else
    BUILD_CMD="$BUILD_CMD -project \"$PROJECT_PATH\""
fi
BUILD_CMD="$BUILD_CMD -scheme PreviewHost"
BUILD_CMD="$BUILD_CMD -destination \"platform=iOS Simulator,id=$SIM_UDID\""
BUILD_CMD="$BUILD_CMD -derivedDataPath \"/tmp/preview-dynamic-dd\""

if [[ "$VERBOSE" != "true" ]]; then
    BUILD_CMD="$BUILD_CMD 2>&1 | tail -20"
fi

eval $BUILD_CMD

BUILD_EXIT=${PIPESTATUS[0]}

# Cleanup function
cleanup_target() {
    if [[ "$KEEP" != "true" ]]; then
        log_info "Cleaning up..."
        rm -rf "$PREVIEW_DIR"
        ruby -r xcodeproj -e "
          proj = Xcodeproj::Project.open('$PROJECT_PATH')
          target = proj.targets.find { |t| t.name == 'PreviewHost' }
          target&.remove_from_project
          proj.main_group.groups.each { |g| g.remove_from_project if g.name == 'PreviewHost' }
          proj.save
        " 2>/dev/null || true
        rm -f "$PROJECT_PATH/xcshareddata/xcschemes/PreviewHost.xcscheme" 2>/dev/null || true
    fi
}

if [[ $BUILD_EXIT -ne 0 ]]; then
    log_error "Build failed"
    cleanup_target
    exit 1
fi

log_success "Build completed"

# Find and run app
APP_PATH=$(find /tmp/preview-dynamic-dd -name "PreviewHost.app" -type d 2>/dev/null | head -1)

if [[ -z "$APP_PATH" ]]; then
    log_error "Could not find built app"
    cleanup_target
    exit 1
fi

log_info "Installing and launching..."

# Terminate any existing instance first
xcrun simctl terminate "$SIM_UDID" "com.preview.host" 2>/dev/null || true

# Install the app
xcrun simctl install "$SIM_UDID" "$APP_PATH"

# Open Simulator app to ensure it's active and frontmost
open -a Simulator --args -CurrentDeviceUDID "$SIM_UDID"
sleep 1

# Launch our preview app (without blocking console)
xcrun simctl launch "$SIM_UDID" "com.preview.host" 2>&1 || true

# Wait for app to render - SwiftUI apps need time to layout
sleep 3

# Try to bring the app to foreground by launching again (no-op if already running)
xcrun simctl launch "$SIM_UDID" "com.preview.host" 2>&1 || true
sleep 1

log_info "Capturing screenshot..."
mkdir -p "$(dirname "$OUTPUT")"
xcrun simctl io "$SIM_UDID" screenshot "$OUTPUT"

xcrun simctl terminate "$SIM_UDID" "com.preview.host" 2>/dev/null || true

cleanup_target

if [[ -f "$OUTPUT" ]]; then
    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    log_success "Preview captured: $OUTPUT ($SIZE)"
    echo ""
    echo "PREVIEW_PATH=$OUTPUT"
else
    log_error "Failed to capture screenshot"
    exit 1
fi
