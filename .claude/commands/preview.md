# /preview - Build and Capture SwiftUI Preview

Build a SwiftUI view and capture its rendered output for visual analysis.

## Arguments

$ARGUMENTS - File path, or options like --scheme, --workspace, --capture-only

## Instructions

You are the preview capture assistant. Your job is to build SwiftUI previews and analyze their visual output.

**Note:** Set the `PREVIEW_BUILD_PATH` environment variable to the installation directory, or update the paths below.

### Unified Entry Point

For most cases, use the unified `preview` script which auto-detects the best approach:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview \
  "<path-to-file.swift>" \
  --output /tmp/preview.png
```

This will automatically:
1. Detect if the file has a `#Preview` block
2. Find the associated Xcode project or SPM package
3. Use dynamic preview injection for fast builds (~3-4 seconds)
4. Fall back to full scheme builds when needed

### Preview Modes

#### Mode 1: Dynamic Preview Injection (Fastest - Recommended)

For files with `#Preview` in an Xcode project, this injects a minimal PreviewHost target:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-dynamic.sh \
  "<path-to-file.swift>" \
  --project "<path.xcodeproj>" \
  --output /tmp/preview.png
```

**Advantages:**
- Builds only the required modules (3-4 seconds vs minutes)
- Works with static modules/libraries
- Automatically includes resource bundles (Tuist and standard naming)
- No pre-existing preview scheme required

#### Mode 2: SPM Package

For files in Swift Package Manager packages:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-spm.sh \
  "<path-to-file.swift>" \
  --output /tmp/preview.png
```

#### Mode 3: Standalone Swift File (No Dependencies)

For Swift files that only use system frameworks (SwiftUI, UIKit, Foundation):

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-minimal.sh \
  "<path-to-file.swift>" \
  --output /tmp/preview.png
```

#### Mode 4: Capture Current Simulator

Just screenshot whatever is currently on screen:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/capture-simulator.sh \
  --output /tmp/preview.png
```

### After Capture: Analyze the Screenshot

1. Use the Read tool to view the PNG:
```
Read /tmp/preview.png
```

2. Provide analysis:
   - **Layout**: Structure and arrangement
   - **Visual elements**: Buttons, text, images
   - **Styling**: Colors, fonts, spacing
   - **Issues**: Alignment, overflow, accessibility
   - **Suggestions**: Improvements

### Example Workflows

**Preview a component from an Xcode project:**
```
User: /preview ~/MyApp/Modules/Components/Button.swift
→ Auto-detects MyApp.xcodeproj
→ Uses preview-dynamic.sh for fast build (~3 seconds)
→ Capture screenshot showing Button component
→ Analyze visual output
```

**Preview from an SPM package:**
```
User: /preview ~/MyPackage/Sources/UI/Card.swift
→ Detects Package.swift
→ Uses preview-spm.sh
→ Capture screenshot
→ Analyze visual output
```

**Preview a standalone SwiftUI file:**
```
User: /preview MyView.swift
→ Detects system-only imports
→ Use preview-minimal.sh to build minimal host
→ Capture screenshot
→ Analyze visual output
```

**Just capture current simulator:**
```
User: /preview --capture-only
→ Screenshot current simulator state
→ Analyze what's shown
```

### Error Handling

- **No simulator booted**: Run `sim-manager.sh boot "iPhone 17 Pro"`
- **Build failure**: Show error, suggest fixes, offer to retry
- **Resource bundle crash**: The dynamic script auto-includes Tuist and common bundle patterns
- **Missing imports**: Check if the target module needs to be added to imports
- **Deployment target mismatch**: The scripts auto-detect iOS version from project/package
