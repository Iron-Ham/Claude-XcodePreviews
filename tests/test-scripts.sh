#!/bin/bash
#
# Test suite for preview-build shell scripts
# Validates bug fixes and expected behaviors without requiring Xcode/simulator
#
# Usage: ./tests/test-scripts.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
ERRORS=""

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: $1"
    echo "  FAIL: $1"
}

section() {
    echo ""
    echo "=== $1 ==="
}

#=============================================================================
# Test: sim-manager.sh defines SCRIPT_DIR (fixes #7)
#=============================================================================
section "sim-manager.sh SCRIPT_DIR definition"

if grep -q 'SCRIPT_DIR=' "$PROJECT_DIR/scripts/sim-manager.sh"; then
    pass "SCRIPT_DIR is defined in sim-manager.sh"
else
    fail "SCRIPT_DIR is NOT defined in sim-manager.sh"
fi

# Verify it uses the standard pattern
if grep -q 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE\[0\]}")" && pwd)"' "$PROJECT_DIR/scripts/sim-manager.sh"; then
    pass "SCRIPT_DIR uses the standard BASH_SOURCE pattern"
else
    fail "SCRIPT_DIR does not use the standard BASH_SOURCE pattern"
fi

#=============================================================================
# Test: preview script forwards --workspace flag (fixes #9)
#=============================================================================
section "preview script --workspace forwarding"

# The exec call for preview-tool preview should include WORKSPACE
# Specifically check the preview-tool exec block (near --project "$PROJECT")
if grep -A5 'PREVIEW_TOOL.*preview' "$PROJECT_DIR/scripts/preview" | grep -q 'WORKSPACE.*--workspace'; then
    pass "preview script forwards --workspace to preview-tool"
else
    fail "preview script does NOT forward --workspace to preview-tool"
fi

#=============================================================================
# Test: preview-module.sh verbose flag logic (fixes #10)
#=============================================================================
section "preview-module.sh verbose flag"

# Should NOT use ${VERBOSE:+-quiet} pattern (the inverted logic)
INVERTED_COUNT=$(grep -c '${VERBOSE:+-quiet}' "$PROJECT_DIR/scripts/preview-module.sh" || true)
if [[ "$INVERTED_COUNT" -eq 0 ]]; then
    pass "No inverted \${VERBOSE:+-quiet} pattern found"
else
    fail "Found $INVERTED_COUNT instances of inverted \${VERBOSE:+-quiet} pattern"
fi

# Verify it uses explicit comparison instead
if grep -q 'VERBOSE.*!=.*true.*&&.*-quiet\|VERBOSE.*!=.*true.*then' "$PROJECT_DIR/scripts/preview-module.sh"; then
    pass "Uses explicit VERBOSE comparison for -quiet flag"
else
    fail "Does not use explicit VERBOSE comparison for -quiet flag"
fi

#=============================================================================
# Test: pipefail is set in scripts (fixes #11)
#=============================================================================
section "pipefail in scripts"

for script in preview preview-build.sh preview-module.sh; do
    if grep -q 'pipefail' "$PROJECT_DIR/scripts/$script"; then
        pass "$script has pipefail set"
    else
        fail "$script does NOT have pipefail set"
    fi
done

#=============================================================================
# Test: preview-module.sh has PIPESTATUS check for SPM build (fixes #11)
#=============================================================================
section "preview-module.sh PIPESTATUS checks"

# Count PIPESTATUS checks - should be at least 3 (SPM + dependency build + preview host)
PIPESTATUS_COUNT=$(grep -c 'PIPESTATUS\[0\]' "$PROJECT_DIR/scripts/preview-module.sh" || true)
if [[ "$PIPESTATUS_COUNT" -ge 3 ]]; then
    pass "preview-module.sh has $PIPESTATUS_COUNT PIPESTATUS checks (expected >= 3)"
else
    fail "preview-module.sh has only $PIPESTATUS_COUNT PIPESTATUS checks (expected >= 3)"
fi

#=============================================================================
# Test: xcode-preview.sh auto-detection uses find, not -f glob (fixes #12)
#=============================================================================
section "xcode-preview.sh auto-detection"

# Should NOT use [[ -f "*.xcworkspace" ]] pattern
if grep -q '\[\[ -f "\*\.xc' "$PROJECT_DIR/scripts/xcode-preview.sh"; then
    fail "xcode-preview.sh still uses broken [[ -f \"*.xc...\" ]] pattern"
else
    pass "xcode-preview.sh does not use broken glob-in-test pattern"
fi

# Should use find or similar for detection
if grep -q 'find.*xcworkspace\|find.*xcodeproj' "$PROJECT_DIR/scripts/xcode-preview.sh"; then
    pass "xcode-preview.sh uses find for auto-detection"
else
    fail "xcode-preview.sh does not use find for auto-detection"
fi

#=============================================================================
# Test: preview-build.sh strips @main from source files (fixes #13)
#=============================================================================
section "preview-build.sh @main stripping"

# The copy to TargetView.swift should use sed to strip @main
if grep -q "sed.*@main.*TargetView" "$PROJECT_DIR/scripts/preview-build.sh"; then
    pass "preview-build.sh strips @main when creating TargetView.swift"
else
    fail "preview-build.sh does NOT strip @main when creating TargetView.swift"
fi

# Verify no dead code (duplicate PreviewHostApp.swift creation)
HOST_APP_COUNT=$(grep -c 'PreviewHostApp.swift' "$PROJECT_DIR/scripts/preview-build.sh" || true)
if [[ "$HOST_APP_COUNT" -le 3 ]]; then
    pass "No duplicate PreviewHostApp.swift creation (count: $HOST_APP_COUNT)"
else
    fail "Possible duplicate PreviewHostApp.swift creation (count: $HOST_APP_COUNT)"
fi

#=============================================================================
# Test: ProjectInjector.swift initializes packageProductDependencies (fixes #8)
#=============================================================================
section "ProjectInjector.swift packageProductDependencies initialization"

if grep -q 'packageProductDependencies.*=.*packageProductDependencies.*??.*\[\]' \
    "$PROJECT_DIR/tools/preview-tool/Sources/ProjectInjector.swift"; then
    pass "packageProductDependencies is nil-coalesced to empty array before use"
else
    fail "packageProductDependencies is NOT initialized before use"
fi

#=============================================================================
# Test: All scripts define SCRIPT_DIR consistently
#=============================================================================
section "Consistent SCRIPT_DIR definitions"

for script in preview preview-build.sh preview-minimal.sh preview-module.sh \
              capture-simulator.sh sim-manager.sh xcode-preview.sh; do
    SCRIPT_PATH="$PROJECT_DIR/scripts/$script"
    if [[ -f "$SCRIPT_PATH" ]]; then
        if grep -q 'SCRIPT_DIR=' "$SCRIPT_PATH"; then
            pass "$script defines SCRIPT_DIR"
        else
            # Not all scripts need SCRIPT_DIR, only flag if they reference it
            if grep -q '$SCRIPT_DIR\|${SCRIPT_DIR}' "$SCRIPT_PATH"; then
                fail "$script references SCRIPT_DIR but does not define it"
            else
                pass "$script does not need SCRIPT_DIR (no references)"
            fi
        fi
    fi
done

#=============================================================================
# Test: preview-tool respects explicit --project over workspace discovery (#25)
#=============================================================================
section "preview-tool --project precedence"

MAIN_SWIFT="$PROJECT_DIR/tools/preview-tool/Sources/CLI/main.swift"
if grep -q 'if let project = args.project' "$MAIN_SWIFT"; then
    pass "preview-tool checks explicit --project first"
else
    fail "preview-tool does not prioritize explicit --project"
fi

# Verify the old pattern (workspace-first) is gone
if grep -q 'if let workspace = args.workspace' "$MAIN_SWIFT" && \
   ! grep -B2 'if let workspace = args.workspace' "$MAIN_SWIFT" | grep -q 'else'; then
    fail "preview-tool still prioritizes workspace over explicit project"
else
    pass "preview-tool correctly falls back to workspace discovery"
fi

#=============================================================================
# Test: PreviewHost directory uses PID-isolated path (#26)
#=============================================================================
section "PID-isolated PreviewHost directory"

if grep -q 'preview-host-.*processIdentifier' "$MAIN_SWIFT"; then
    pass "PreviewHost directory uses PID-isolated path"
else
    fail "PreviewHost directory uses fixed project-relative path"
fi

# Ensure the old fixed "PreviewHost" path is not used for the project-relative directory
# (the SPM path uses PreviewHost inside a temp dir which is safe)
if grep -q 'projectDir.*appendingPathComponent("PreviewHost")' "$MAIN_SWIFT"; then
    fail "Fixed 'PreviewHost' path still used for project-relative directory"
else
    pass "No fixed project-relative 'PreviewHost' directory path"
fi

#=============================================================================
# Test: ImportCollector extracts only module name, not declaration path (#27)
#=============================================================================
section "ImportCollector module name extraction"

EXTRACTOR="$PROJECT_DIR/tools/preview-tool/Sources/PreviewExtractor.swift"
# Should use node.path.first, not join all components
if grep -q 'node.path.first' "$EXTRACTOR"; then
    pass "ImportCollector uses first path component only"
else
    fail "ImportCollector joins all path components"
fi

if grep -q 'joined(separator: "\.")' "$EXTRACTOR"; then
    fail "ImportCollector still joins path components with dot"
else
    pass "No dot-joined import path construction"
fi

#=============================================================================
# Test: preview script does not use exec for dynamic injection (#30)
#=============================================================================
section "preview script dynamic injection fallback"

# The preview-tool preview invocation should NOT use exec (so fallback works)
PREVIEW_SCRIPT="$PROJECT_DIR/scripts/preview"
# Find the dynamic injection block - it should use 'if "$PREVIEW_TOOL"' not 'exec "$PREVIEW_TOOL" preview'
if grep -q 'exec.*\$PREVIEW_TOOL.*preview[^-]' "$PREVIEW_SCRIPT"; then
    fail "preview script still uses exec for dynamic injection (blocks fallback)"
else
    pass "preview script does not use exec for dynamic injection"
fi

# Should have a fallback warning message
if grep -q 'falling back to scheme build' "$PREVIEW_SCRIPT"; then
    pass "preview script has fallback warning on injection failure"
else
    fail "preview script missing fallback warning"
fi

#=============================================================================
# Test: preview script discovers project context before standalone check (#31)
#=============================================================================
section "preview script project discovery ordering"

# The parent-directory search (Package.swift) must appear BEFORE the SYSTEM_ONLY check
SEARCH_LINE=$(grep -n 'Package.swift' "$PREVIEW_SCRIPT" | head -1 | cut -d: -f1)
SYSTEM_LINE=$(grep -n 'SYSTEM_ONLY.*true.*PROJECT.*WORKSPACE' "$PREVIEW_SCRIPT" | head -1 | cut -d: -f1)

if [[ -n "$SEARCH_LINE" && -n "$SYSTEM_LINE" && "$SEARCH_LINE" -lt "$SYSTEM_LINE" ]]; then
    pass "Package.swift search (line $SEARCH_LINE) runs before standalone check (line $SYSTEM_LINE)"
else
    fail "Standalone check runs before Package.swift search (search=$SEARCH_LINE, system=$SYSTEM_LINE)"
fi

#=============================================================================
# Summary
#=============================================================================
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failures:"
    echo -e "$ERRORS"
    echo "================================"
    exit 1
else
    echo "================================"
fi
