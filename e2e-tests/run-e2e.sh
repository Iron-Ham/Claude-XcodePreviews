#!/bin/bash
# End-to-end integration test for preview-tool
# Tests the tool against various real project types

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREVIEW_TOOL="$REPO_ROOT/tools/preview-tool/.build/release/preview-tool"
TEST_ROOT="/tmp/preview-e2e-projects"

# Build the preview-tool first
echo "Building preview-tool..."
swift build -c release --package-path "$REPO_ROOT/tools/preview-tool" 2>&1 | tail -1
echo ""
PASSED=0
FAILED=0
ERRORS=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

run_test() {
    local test_name="$1"
    shift
    echo -e "\n${BLUE}━━━ TEST: $test_name ━━━${NC}"
    echo "  CMD: $PREVIEW_TOOL $*"

    local output
    local exit_code=0
    output=$("$PREVIEW_TOOL" "$@" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "  ${GREEN}✓ PASSED${NC} (exit 0)"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAILED${NC} (exit $exit_code)"
        echo "$output" | tail -5 | sed 's/^/    /'
        FAILED=$((FAILED + 1))
        ERRORS="$ERRORS\n  - $test_name"
    fi
}

# Expect failure (tool should exit non-zero)
run_test_expect_fail() {
    local test_name="$1"
    shift
    echo -e "\n${BLUE}━━━ TEST: $test_name (expect failure) ━━━${NC}"
    echo "  CMD: $PREVIEW_TOOL $*"

    local output
    local exit_code=0
    output=$("$PREVIEW_TOOL" "$@" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo -e "  ${GREEN}✓ PASSED${NC} (correctly failed with exit $exit_code)"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}✗ FAILED${NC} (should have failed but exited 0)"
        FAILED=$((FAILED + 1))
        ERRORS="$ERRORS\n  - $test_name (expected failure)"
    fi
}

# Check that a file exists and contains expected content
check_file() {
    local file="$1"
    local expected="$2"
    local test_name="$3"

    if [[ ! -f "$file" ]]; then
        echo -e "  ${RED}✗ File not found: $file${NC}"
        FAILED=$((FAILED + 1))
        ERRORS="$ERRORS\n  - $test_name: file not found"
        return 1
    fi

    if [[ -n "$expected" ]]; then
        if grep -q "$expected" "$file"; then
            echo -e "  ${GREEN}✓ $test_name${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "  ${RED}✗ $test_name: expected '$expected' not found${NC}"
            FAILED=$((FAILED + 1))
            ERRORS="$ERRORS\n  - $test_name: content mismatch"
            return 1
        fi
    else
        echo -e "  ${GREEN}✓ $test_name (file exists)${NC}"
        PASSED=$((PASSED + 1))
    fi
}

# Clean up previous test runs
rm -rf "$TEST_ROOT"
mkdir -p "$TEST_ROOT"

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Preview Tool End-to-End Integration Tests   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# ─────────────────────────────────────────────────
# PROJECT 1: Simple single-file app target
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 1: SimpleApp${NC}"
P1="$TEST_ROOT/SimpleApp"
mkdir -p "$P1/SimpleApp"

cat > "$P1/SimpleApp/ContentView.swift" << 'SWIFT'
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello, World!")
            Image(systemName: "star.fill")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
SWIFT

cat > "$P1/SimpleApp/SimpleAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct SimpleAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
SWIFT

# Create Xcode project using ruby xcodeproj
ruby - "$P1" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "SimpleApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "SimpleApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.SimpleApp'
end
group = proj.main_group.new_group("SimpleApp", "SimpleApp")
%w[ContentView.swift SimpleAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

# Test: preview-tool preview on app-target file
run_test "SimpleApp: preview ContentView" \
    preview --file "$P1/SimpleApp/ContentView.swift" \
    --project "$P1/SimpleApp.xcodeproj" \
    --keep --verbose

# Check that PreviewHost was injected
check_file "$P1/PreviewHost/PreviewHostApp.swift" "PreviewContent" "SimpleApp: PreviewHostApp.swift generated"
check_file "$P1/PreviewHost/_PreviewGenerated.swift" "ContentView" "SimpleApp: _PreviewGenerated.swift has ContentView"

# Check that @main was NOT included in generated file
if grep -q "@main" "$P1/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ SimpleApp: _PreviewGenerated.swift should NOT contain @main${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - SimpleApp: @main leaked into generated file"
else
    echo -e "  ${GREEN}✓ SimpleApp: @main correctly excluded from _PreviewGenerated.swift${NC}"
    PASSED=$((PASSED + 1))
fi

# Cleanup injected target
"$PREVIEW_TOOL" preview --file "$P1/SimpleApp/ContentView.swift" \
    --project "$P1/SimpleApp.xcodeproj" --keep 2>/dev/null || true
rm -rf "$P1/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 2: Multi-file app with complex dependencies
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 2: ComplexApp${NC}"
P2="$TEST_ROOT/ComplexApp"
mkdir -p "$P2/ComplexApp"

cat > "$P2/ComplexApp/ProfileView.swift" << 'SWIFT'
import SwiftUI

struct ProfileView: View {
    let user: UserModel
    var body: some View {
        VStack {
            Text(user.name)
            Text(user.email)
            Badge(level: user.level)
        }
    }
}

#Preview {
    ProfileView(user: UserModel(name: "Test", email: "test@test.com", level: .gold))
}
SWIFT

cat > "$P2/ComplexApp/UserModel.swift" << 'SWIFT'
import Foundation

struct UserModel {
    let name: String
    let email: String
    let level: MembershipLevel
}

struct UnrelatedModel {
    let unused: String
}
SWIFT

cat > "$P2/ComplexApp/Badge.swift" << 'SWIFT'
import SwiftUI

struct Badge: View {
    let level: MembershipLevel
    var body: some View {
        Text(level.displayName)
            .padding(4)
            .background(level.color)
    }
}
SWIFT

cat > "$P2/ComplexApp/MembershipLevel.swift" << 'SWIFT'
import SwiftUI

enum MembershipLevel: String {
    case silver, gold, platinum

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .silver: .gray
        case .gold: .yellow
        case .platinum: .blue
        }
    }
}
SWIFT

cat > "$P2/ComplexApp/NetworkService.swift" << 'SWIFT'
import Foundation

class NetworkService {
    func fetchUsers() async throws -> [UserModel] { [] }
}

class AnalyticsService {
    func track(event: String) {}
}
SWIFT

cat > "$P2/ComplexApp/ComplexAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct ComplexAppApp: App {
    var body: some Scene {
        WindowGroup {
            ProfileView(user: UserModel(name: "Main", email: "a@b.com", level: .silver))
        }
    }
}
SWIFT

ruby - "$P2" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "ComplexApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "ComplexApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.ComplexApp'
end
group = proj.main_group.new_group("ComplexApp", "ComplexApp")
%w[ProfileView.swift UserModel.swift Badge.swift MembershipLevel.swift NetworkService.swift ComplexAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "ComplexApp: preview ProfileView" \
    preview --file "$P2/ComplexApp/ProfileView.swift" \
    --project "$P2/ComplexApp.xcodeproj" \
    --keep --verbose

check_file "$P2/PreviewHost/_PreviewGenerated.swift" "ProfileView" "ComplexApp: ProfileView included"
check_file "$P2/PreviewHost/_PreviewGenerated.swift" "UserModel" "ComplexApp: UserModel included (transitive dep)"
check_file "$P2/PreviewHost/_PreviewGenerated.swift" "Badge" "ComplexApp: Badge included (referenced in body)"
check_file "$P2/PreviewHost/_PreviewGenerated.swift" "MembershipLevel" "ComplexApp: MembershipLevel included (transitive)"

# Declaration-level precision: UnrelatedModel should NOT be included
if grep -q "UnrelatedModel" "$P2/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ComplexApp: UnrelatedModel should NOT be in generated file (declaration-level precision)${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - ComplexApp: UnrelatedModel incorrectly included"
else
    echo -e "  ${GREEN}✓ ComplexApp: UnrelatedModel correctly excluded (declaration-level precision)${NC}"
    PASSED=$((PASSED + 1))
fi

# NetworkService/AnalyticsService should NOT be included
if grep -q "NetworkService" "$P2/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ComplexApp: NetworkService should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - ComplexApp: NetworkService incorrectly included"
else
    echo -e "  ${GREEN}✓ ComplexApp: NetworkService correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

# @main should NOT be included
if grep -q "@main" "$P2/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ComplexApp: @main should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✓ ComplexApp: @main correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

rm -rf "$P2/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 3: Module-based project (Modules/SomeName/)
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 3: ModularApp (Modules directory)${NC}"
P3="$TEST_ROOT/ModularApp"
mkdir -p "$P3/ModularApp"
mkdir -p "$P3/Modules/Components/Sources"

cat > "$P3/Modules/Components/Sources/ChipView.swift" << 'SWIFT'
import SwiftUI

public struct ChipView: View {
    let text: String
    let style: ChipStyle

    public var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.backgroundColor)
            .cornerRadius(12)
    }
}

#Preview {
    ChipView(text: "Hello", style: .primary)
}
SWIFT

cat > "$P3/Modules/Components/Sources/ChipStyle.swift" << 'SWIFT'
import SwiftUI

public enum ChipStyle {
    case primary, secondary, outlined

    var backgroundColor: Color {
        switch self {
        case .primary: .blue
        case .secondary: .gray
        case .outlined: .clear
        }
    }
}
SWIFT

cat > "$P3/ModularApp/ModularAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct ModularAppApp: App {
    var body: some Scene {
        WindowGroup { Text("Hi") }
    }
}
SWIFT

ruby - "$P3" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "ModularApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)

# Create framework target for Components module
fw_target = proj.new_target(:framework, "Components", :ios, "17.0")
fw_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.Components'
  config.build_settings['DEFINES_MODULE'] = 'YES'
end
fw_group = proj.main_group.new_group("Components", "Modules/Components/Sources")
%w[ChipView.swift ChipStyle.swift].each do |f|
  ref = fw_group.new_file(f)
  fw_target.source_build_phase.add_file_reference(ref)
end

# Create app target
app_target = proj.new_target(:application, "ModularApp", :ios, "17.0")
app_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.ModularApp'
end
app_group = proj.main_group.new_group("ModularApp", "ModularApp")
ref = app_group.new_file("ModularAppApp.swift")
app_target.source_build_phase.add_file_reference(ref)

proj.save
RUBY

# Test: preview a file in a Modules/ directory — should auto-detect target "Components"
run_test "ModularApp: preview ChipView (auto-detect module target)" \
    preview --file "$P3/Modules/Components/Sources/ChipView.swift" \
    --project "$P3/ModularApp.xcodeproj" \
    --keep --verbose

# For module target, no _PreviewGenerated.swift should be created (module files skip resolver)
# Instead PreviewHost should import the module
check_file "$P3/PreviewHost/PreviewHostApp.swift" "import Components" "ModularApp: imports Components module"

rm -rf "$P3/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 4: Extension-heavy project
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 4: ExtensionApp${NC}"
P4="$TEST_ROOT/ExtensionApp"
mkdir -p "$P4/ExtensionApp"

cat > "$P4/ExtensionApp/SettingsView.swift" << 'SWIFT'
import SwiftUI

struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        List {
            Text(settings.displaySummary)
            Toggle("Dark Mode", isOn: .constant(settings.isDarkMode))
        }
    }
}

#Preview {
    SettingsView(settings: AppSettings(isDarkMode: true, fontSize: 14))
}
SWIFT

cat > "$P4/ExtensionApp/AppSettings.swift" << 'SWIFT'
import Foundation

struct AppSettings {
    let isDarkMode: Bool
    let fontSize: Int
}
SWIFT

cat > "$P4/ExtensionApp/AppSettings+Display.swift" << 'SWIFT'
import Foundation

extension AppSettings {
    var displaySummary: String {
        "Dark: \(isDarkMode), Size: \(fontSize)"
    }
}
SWIFT

cat > "$P4/ExtensionApp/String+Utils.swift" << 'SWIFT'
import Foundation

extension String {
    func truncated(to length: Int) -> String {
        if count <= length { return self }
        return prefix(length) + "..."
    }
}
SWIFT

cat > "$P4/ExtensionApp/ExtensionAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct ExtensionAppApp: App {
    var body: some Scene {
        WindowGroup { Text("Hi") }
    }
}
SWIFT

ruby - "$P4" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "ExtensionApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "ExtensionApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.ExtensionApp'
end
group = proj.main_group.new_group("ExtensionApp", "ExtensionApp")
%w[SettingsView.swift AppSettings.swift AppSettings+Display.swift String+Utils.swift ExtensionAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "ExtensionApp: preview SettingsView" \
    preview --file "$P4/ExtensionApp/SettingsView.swift" \
    --project "$P4/ExtensionApp.xcodeproj" \
    --keep --verbose

check_file "$P4/PreviewHost/_PreviewGenerated.swift" "AppSettings" "ExtensionApp: AppSettings included"
check_file "$P4/PreviewHost/_PreviewGenerated.swift" "extension AppSettings" "ExtensionApp: AppSettings extension included"
check_file "$P4/PreviewHost/_PreviewGenerated.swift" "displaySummary" "ExtensionApp: displaySummary method included"

# String extension from non-contributing file should NOT be included
if grep -q "truncated" "$P4/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ExtensionApp: String extension should NOT be included${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - ExtensionApp: String extension incorrectly included"
else
    echo -e "  ${GREEN}✓ ExtensionApp: String extension correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

if grep -q "@main" "$P4/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ExtensionApp: @main should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✓ ExtensionApp: @main correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

rm -rf "$P4/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 5: Complex #Preview bodies
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 5: ComplexPreview${NC}"
P5="$TEST_ROOT/ComplexPreview"
mkdir -p "$P5/ComplexPreview"

cat > "$P5/ComplexPreview/ComplexView.swift" << 'SWIFT'
import SwiftUI

struct ComplexView: View {
    let items: [String]
    @State private var showSheet = false

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { item in
                Button(item) {
                    showSheet = true
                }
            }
            .navigationTitle("Items")
            .sheet(isPresented: $showSheet) {
                Text("Selected an item")
            }
        }
    }
}

#Preview {
    ComplexView(items: [
        "First item with \"quotes\"",
        "Second {braces} item",
        "Third \\ backslash",
    ])
}
SWIFT

cat > "$P5/ComplexPreview/ComplexPreviewApp.swift" << 'SWIFT'
import SwiftUI

@main
struct ComplexPreviewApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P5" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "ComplexPreview.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "ComplexPreview", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.ComplexPreview'
end
group = proj.main_group.new_group("ComplexPreview", "ComplexPreview")
%w[ComplexView.swift ComplexPreviewApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "ComplexPreview: complex body with special chars" \
    preview --file "$P5/ComplexPreview/ComplexView.swift" \
    --project "$P5/ComplexPreview.xcodeproj" \
    --keep --verbose

check_file "$P5/PreviewHost/PreviewHostApp.swift" "PreviewContent" "ComplexPreview: PreviewHostApp generated"
# Verify the preview body was extracted correctly (should have the items array)
check_file "$P5/PreviewHost/PreviewHostApp.swift" "ComplexView" "ComplexPreview: body contains ComplexView instantiation"

rm -rf "$P5/PreviewHost"

# ─────────────────────────────────────────────────
# ERROR CASES
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Error Case Tests${NC}"

# No file specified
run_test_expect_fail "Error: no --file" preview --project "$P1/SimpleApp.xcodeproj"

# File not found
run_test_expect_fail "Error: file not found" preview --file "/nonexistent/file.swift" --project "$P1/SimpleApp.xcodeproj"

# No project or workspace
run_test_expect_fail "Error: no --project or --workspace" preview --file "$P1/SimpleApp/ContentView.swift"

# No #Preview in file
cat > "/tmp/preview-e2e-no-preview.swift" << 'SWIFT'
import SwiftUI
struct NoPreview: View {
    var body: some View { Text("Hi") }
}
SWIFT
run_test_expect_fail "Error: no #Preview in file" preview --file "/tmp/preview-e2e-no-preview.swift" --project "$P1/SimpleApp.xcodeproj"

# Unknown argument warning (should still succeed if other args are valid, but we verify it runs)
# Actually this will fail because the tool still needs a valid simulator etc.
# Just test that parsing doesn't crash
echo -e "\n${BLUE}━━━ TEST: Unknown argument warning ━━━${NC}"
output=$("$PREVIEW_TOOL" preview --file "$P1/SimpleApp/ContentView.swift" --project "$P1/SimpleApp.xcodeproj" --typo-arg --keep 2>&1 || true)
if echo "$output" | grep -q "Unknown argument: --typo-arg"; then
    echo -e "  ${GREEN}✓ Unknown argument warning displayed${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ Unknown argument warning NOT displayed${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - Unknown argument warning not displayed"
fi

# ─────────────────────────────────────────────────
# RESOLVE SUBCOMMAND (backward compat)
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Resolve subcommand tests${NC}"

run_test "Resolve: basic file-level resolution" \
    resolve --start "$P2/ComplexApp/ProfileView.swift" --sources-dir "$P2/ComplexApp"

# Verify JSON output from resolve
echo -e "\n${BLUE}━━━ TEST: Resolve: JSON output structure ━━━${NC}"
resolve_output=$("$PREVIEW_TOOL" resolve --start "$P2/ComplexApp/ProfileView.swift" --sources-dir "$P2/ComplexApp" 2>/dev/null)
if echo "$resolve_output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'resolvedFiles' in d; assert 'stats' in d; print('valid JSON')" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Resolve: valid JSON with expected keys${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ Resolve: invalid JSON output${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - Resolve: invalid JSON output"
fi

# Resolve: verify @main file is NOT in resolvedFiles (BFS won't reach it from ProfileView)
echo -e "\n${BLUE}━━━ TEST: Resolve: @main file not in resolvedFiles ━━━${NC}"
if echo "$resolve_output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
resolved = d.get('resolvedFiles', [])
has_main = any('ComplexAppApp' in f for f in resolved)
if not has_main:
    print('correctly omitted')
    sys.exit(0)
else:
    print('incorrectly included')
    sys.exit(1)
" 2>/dev/null; then
    echo -e "  ${GREEN}✓ Resolve: @main file not in resolved files${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "  ${RED}✗ Resolve: @main file was incorrectly included in resolvedFiles${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - Resolve: @main file included"
fi

# ─────────────────────────────────────────────────
# PROJECT 6: Generics & Property Wrappers
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 6: GenericsApp${NC}"
P6="$TEST_ROOT/GenericsApp"
mkdir -p "$P6/GenericsApp"

cat > "$P6/GenericsApp/GenericCard.swift" << 'SWIFT'
import SwiftUI

struct GenericCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            content()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

#Preview {
    GenericCard(title: "Test Card") {
        Text("Card content")
        Text("More content")
    }
}
SWIFT

cat > "$P6/GenericsApp/ThemeManager.swift" << 'SWIFT'
import SwiftUI

@propertyWrapper
struct AppTheme: DynamicProperty {
    @AppStorage("theme") var theme: String = "light"

    var wrappedValue: String {
        get { theme }
        nonmutating set { theme = newValue }
    }
}

class ThemeManager: ObservableObject {
    @Published var primaryColor: Color = .blue
    @Published var fontSize: CGFloat = 16
    static let shared = ThemeManager()
}
SWIFT

cat > "$P6/GenericsApp/GenericsAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct GenericsAppApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P6" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "GenericsApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "GenericsApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.GenericsApp'
end
group = proj.main_group.new_group("GenericsApp", "GenericsApp")
%w[GenericCard.swift ThemeManager.swift GenericsAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "GenericsApp: preview GenericCard with @ViewBuilder" \
    preview --file "$P6/GenericsApp/GenericCard.swift" \
    --project "$P6/GenericsApp.xcodeproj" \
    --keep --verbose

check_file "$P6/PreviewHost/_PreviewGenerated.swift" "GenericCard" "GenericsApp: GenericCard included"

# ThemeManager should NOT be included (not referenced by GenericCard)
if grep -q "ThemeManager" "$P6/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ GenericsApp: ThemeManager should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - GenericsApp: ThemeManager incorrectly included"
else
    echo -e "  ${GREEN}✓ GenericsApp: ThemeManager correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

rm -rf "$P6/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 7: Protocol-heavy with nested types
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 7: ProtocolApp${NC}"
P7="$TEST_ROOT/ProtocolApp"
mkdir -p "$P7/ProtocolApp"

cat > "$P7/ProtocolApp/Displayable.swift" << 'SWIFT'
import Foundation

protocol Displayable {
    var displayTitle: String { get }
    var displaySubtitle: String { get }
}
SWIFT

cat > "$P7/ProtocolApp/Item.swift" << 'SWIFT'
import Foundation

struct Item: Displayable, Identifiable {
    let id = UUID()
    let name: String
    let count: Int

    var displayTitle: String { name }
    var displaySubtitle: String { "\(count) items" }

    enum Category: String, CaseIterable {
        case food, clothing, electronics

        var icon: String {
            switch self {
            case .food: "fork.knife"
            case .clothing: "tshirt"
            case .electronics: "laptopcomputer"
            }
        }
    }
}
SWIFT

cat > "$P7/ProtocolApp/ItemListView.swift" << 'SWIFT'
import SwiftUI

struct ItemListView: View {
    let items: [Item]

    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.displayTitle)
                    .font(.headline)
                Text(item.displaySubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ItemListView(items: [
        Item(name: "Apple", count: 5),
        Item(name: "Shirt", count: 2),
    ])
}
SWIFT

cat > "$P7/ProtocolApp/UnusedService.swift" << 'SWIFT'
import Foundation

protocol NetworkProtocol {
    func fetch() async throws -> Data
}

class UnusedService: NetworkProtocol {
    func fetch() async throws -> Data { Data() }
}
SWIFT

cat > "$P7/ProtocolApp/ProtocolAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct ProtocolAppApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P7" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "ProtocolApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "ProtocolApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.ProtocolApp'
end
group = proj.main_group.new_group("ProtocolApp", "ProtocolApp")
%w[Displayable.swift Item.swift ItemListView.swift UnusedService.swift ProtocolAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "ProtocolApp: preview ItemListView (protocols + nested types)" \
    preview --file "$P7/ProtocolApp/ItemListView.swift" \
    --project "$P7/ProtocolApp.xcodeproj" \
    --keep --verbose

check_file "$P7/PreviewHost/_PreviewGenerated.swift" "ItemListView" "ProtocolApp: ItemListView included"
check_file "$P7/PreviewHost/_PreviewGenerated.swift" "ItemRow" "ProtocolApp: ItemRow included (same-file type)"
check_file "$P7/PreviewHost/_PreviewGenerated.swift" "struct Item" "ProtocolApp: Item included (transitive)"
check_file "$P7/PreviewHost/_PreviewGenerated.swift" "Displayable" "ProtocolApp: Displayable protocol included"

# UnusedService should NOT be included
if grep -q "UnusedService" "$P7/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ ProtocolApp: UnusedService should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - ProtocolApp: UnusedService incorrectly included"
else
    echo -e "  ${GREEN}✓ ProtocolApp: UnusedService correctly excluded${NC}"
    PASSED=$((PASSED + 1))
fi

rm -rf "$P7/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 8: ObservableObject + EnvironmentObject
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 8: StateApp (Observable/Environment)${NC}"
P8="$TEST_ROOT/StateApp"
mkdir -p "$P8/StateApp"

cat > "$P8/StateApp/AppState.swift" << 'SWIFT'
import SwiftUI

class AppState: ObservableObject {
    @Published var username: String = "Guest"
    @Published var isLoggedIn: Bool = false
    @Published var itemCount: Int = 0
}
SWIFT

cat > "$P8/StateApp/DashboardView.swift" << 'SWIFT'
import SwiftUI

struct DashboardView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome, \(state.username)")
                .font(.title)
            HStack {
                StatusBadge(isActive: state.isLoggedIn)
                Text("\(state.itemCount) items")
            }
        }
        .padding()
    }
}

#Preview {
    DashboardView()
}
SWIFT

cat > "$P8/StateApp/StatusBadge.swift" << 'SWIFT'
import SwiftUI

struct StatusBadge: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.red)
            .frame(width: 12, height: 12)
    }
}
SWIFT

cat > "$P8/StateApp/StateAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct StateAppApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P8" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "StateApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "StateApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.StateApp'
end
group = proj.main_group.new_group("StateApp", "StateApp")
%w[AppState.swift DashboardView.swift StatusBadge.swift StateAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "StateApp: preview DashboardView (ObservableObject + @StateObject)" \
    preview --file "$P8/StateApp/DashboardView.swift" \
    --project "$P8/StateApp.xcodeproj" \
    --keep --verbose

check_file "$P8/PreviewHost/_PreviewGenerated.swift" "DashboardView" "StateApp: DashboardView included"
check_file "$P8/PreviewHost/_PreviewGenerated.swift" "AppState" "StateApp: AppState included (referenced)"
check_file "$P8/PreviewHost/_PreviewGenerated.swift" "StatusBadge" "StateApp: StatusBadge included (referenced)"

rm -rf "$P8/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 9: Multiple #Preview blocks in one file
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 9: MultiPreview${NC}"
P9="$TEST_ROOT/MultiPreview"
mkdir -p "$P9/MultiPreview"

cat > "$P9/MultiPreview/ButtonStyles.swift" << 'SWIFT'
import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(10)
        }
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 2)
                )
        }
    }
}

#Preview("Primary") {
    PrimaryButton(title: "Submit") {}
        .padding()
}

#Preview("Secondary") {
    SecondaryButton(title: "Cancel") {}
        .padding()
}
SWIFT

cat > "$P9/MultiPreview/MultiPreviewApp.swift" << 'SWIFT'
import SwiftUI

@main
struct MultiPreviewApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P9" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "MultiPreview.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "MultiPreview", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.MultiPreview'
end
group = proj.main_group.new_group("MultiPreview", "MultiPreview")
%w[ButtonStyles.swift MultiPreviewApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "MultiPreview: file with multiple #Preview blocks" \
    preview --file "$P9/MultiPreview/ButtonStyles.swift" \
    --project "$P9/MultiPreview.xcodeproj" \
    --keep --verbose

check_file "$P9/PreviewHost/_PreviewGenerated.swift" "PrimaryButton" "MultiPreview: PrimaryButton included"
check_file "$P9/PreviewHost/_PreviewGenerated.swift" "SecondaryButton" "MultiPreview: SecondaryButton included"

# Should NOT contain #Preview in the generated file
if grep -q "#Preview" "$P9/PreviewHost/_PreviewGenerated.swift"; then
    echo -e "  ${RED}✗ MultiPreview: #Preview should NOT be in generated file${NC}"
    FAILED=$((FAILED + 1))
    ERRORS="$ERRORS\n  - MultiPreview: #Preview leaked into generated file"
else
    echo -e "  ${GREEN}✓ MultiPreview: #Preview correctly stripped from generated file${NC}"
    PASSED=$((PASSED + 1))
fi

rm -rf "$P9/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 10: Deep dependency chain (A → B → C → D)
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 10: DeepChainApp${NC}"
P10="$TEST_ROOT/DeepChainApp"
mkdir -p "$P10/DeepChainApp"

cat > "$P10/DeepChainApp/ColorConfig.swift" << 'SWIFT'
import SwiftUI

struct ColorConfig {
    let primary: Color
    let secondary: Color

    static let defaultTheme = ColorConfig(primary: .blue, secondary: .gray)
}
SWIFT

cat > "$P10/DeepChainApp/TextStyle.swift" << 'SWIFT'
import SwiftUI

struct TextStyle {
    let config: ColorConfig
    let fontSize: CGFloat

    var foregroundColor: Color { config.primary }
}
SWIFT

cat > "$P10/DeepChainApp/StyledLabel.swift" << 'SWIFT'
import SwiftUI

struct StyledLabel: View {
    let text: String
    let style: TextStyle

    var body: some View {
        Text(text)
            .font(.system(size: style.fontSize))
            .foregroundColor(style.foregroundColor)
    }
}
SWIFT

cat > "$P10/DeepChainApp/HeaderView.swift" << 'SWIFT'
import SwiftUI

struct HeaderView: View {
    let title: String

    var body: some View {
        StyledLabel(
            text: title,
            style: TextStyle(config: .defaultTheme, fontSize: 24)
        )
        .padding()
    }
}

#Preview {
    HeaderView(title: "Hello World")
}
SWIFT

cat > "$P10/DeepChainApp/DeepChainAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct DeepChainAppApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P10" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "DeepChainApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)
target = proj.new_target(:application, "DeepChainApp", :ios, "17.0")
target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.DeepChainApp'
end
group = proj.main_group.new_group("DeepChainApp", "DeepChainApp")
%w[ColorConfig.swift TextStyle.swift StyledLabel.swift HeaderView.swift DeepChainAppApp.swift].each do |f|
  ref = group.new_file(f)
  target.source_build_phase.add_file_reference(ref)
end
proj.save
RUBY

run_test "DeepChainApp: 4-level transitive dep chain (Header→Styled→TextStyle→Color)" \
    preview --file "$P10/DeepChainApp/HeaderView.swift" \
    --project "$P10/DeepChainApp.xcodeproj" \
    --keep --verbose

check_file "$P10/PreviewHost/_PreviewGenerated.swift" "HeaderView" "DeepChainApp: HeaderView included"
check_file "$P10/PreviewHost/_PreviewGenerated.swift" "StyledLabel" "DeepChainApp: StyledLabel included (depth 1)"
check_file "$P10/PreviewHost/_PreviewGenerated.swift" "TextStyle" "DeepChainApp: TextStyle included (depth 2)"
check_file "$P10/PreviewHost/_PreviewGenerated.swift" "ColorConfig" "DeepChainApp: ColorConfig included (depth 3)"

rm -rf "$P10/PreviewHost"

# ─────────────────────────────────────────────────
# PROJECT 11: Module with multiple frameworks
# ─────────────────────────────────────────────────
echo -e "\n${YELLOW}▸ Setting up Project 11: MultiModuleApp${NC}"
P11="$TEST_ROOT/MultiModuleApp"
mkdir -p "$P11/MultiModuleApp"
mkdir -p "$P11/Modules/UIComponents/Sources"
mkdir -p "$P11/Modules/Models/Sources"

cat > "$P11/Modules/Models/Sources/Product.swift" << 'SWIFT'
import Foundation

public struct Product: Identifiable {
    public let id: String
    public let name: String
    public let price: Double

    public init(id: String, name: String, price: Double) {
        self.id = id
        self.name = name
        self.price = price
    }
}
SWIFT

cat > "$P11/Modules/UIComponents/Sources/ProductCard.swift" << 'SWIFT'
import SwiftUI
import Models

public struct ProductCard: View {
    let product: Product

    public init(product: Product) {
        self.product = product
    }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(product.name)
                .font(.headline)
            Text("$\(product.price, specifier: "%.2f")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    ProductCard(product: Product(id: "1", name: "Test Product", price: 29.99))
}
SWIFT

cat > "$P11/MultiModuleApp/MultiModuleAppApp.swift" << 'SWIFT'
import SwiftUI

@main
struct MultiModuleAppApp: App {
    var body: some Scene {
        WindowGroup { Text("") }
    }
}
SWIFT

ruby - "$P11" << 'RUBY'
require 'xcodeproj'
dir = ARGV[0]
proj_path = File.join(dir, "MultiModuleApp.xcodeproj")
proj = Xcodeproj::Project.new(proj_path)

# Models framework
models_target = proj.new_target(:framework, "Models", :ios, "17.0")
models_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.Models'
  config.build_settings['DEFINES_MODULE'] = 'YES'
end
models_group = proj.main_group.new_group("Models", "Modules/Models/Sources")
ref = models_group.new_file("Product.swift")
models_target.source_build_phase.add_file_reference(ref)

# UIComponents framework (depends on Models)
ui_target = proj.new_target(:framework, "UIComponents", :ios, "17.0")
ui_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.UIComponents'
  config.build_settings['DEFINES_MODULE'] = 'YES'
end
ui_group = proj.main_group.new_group("UIComponents", "Modules/UIComponents/Sources")
ref = ui_group.new_file("ProductCard.swift")
ui_target.source_build_phase.add_file_reference(ref)

# Add Models dependency to UIComponents
ui_target.add_dependency(models_target)

# App target
app_target = proj.new_target(:application, "MultiModuleApp", :ios, "17.0")
app_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.test.MultiModuleApp'
end
app_group = proj.main_group.new_group("MultiModuleApp", "MultiModuleApp")
ref = app_group.new_file("MultiModuleAppApp.swift")
app_target.source_build_phase.add_file_reference(ref)

proj.save
RUBY

run_test "MultiModuleApp: preview ProductCard (UIComponents depends on Models)" \
    preview --file "$P11/Modules/UIComponents/Sources/ProductCard.swift" \
    --project "$P11/MultiModuleApp.xcodeproj" \
    --keep --verbose

# Should use @testable import for UIComponents
check_file "$P11/PreviewHost/PreviewHostApp.swift" "import UIComponents" "MultiModuleApp: imports UIComponents"

rm -rf "$P11/PreviewHost"

# Help flag
run_test "Help: --help exits cleanly" --help

# ─────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────
echo -e "\n${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              TEST RESULTS SUMMARY             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
echo -e "  ${GREEN}Passed:${NC} $PASSED"
echo -e "  ${RED}Failed:${NC} $FAILED"

if [[ $FAILED -gt 0 ]]; then
    echo -e "\n${RED}Failed tests:${NC}"
    echo -e "$ERRORS"
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${NC}"
fi
