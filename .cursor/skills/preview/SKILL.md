---
name: preview-build
description: Build and capture SwiftUI previews for visual analysis. Use when the user asks to preview a SwiftUI view, capture a simulator screenshot, or visually inspect iOS UI components. Supports Xcode projects, SPM packages, and standalone Swift files.
---

# Xcode Preview Capture Skill

Build SwiftUI views and capture screenshots of their rendered output for visual analysis.

## Installation Path

Scripts are located at `${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}/scripts/`

## Available Commands

### Unified Preview (Recommended)

Auto-detects project type and uses the best approach:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview \
  <path-to-file.swift> \
  --output /tmp/preview.png
```

### Quick Capture (Current Simulator)

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/capture-simulator.sh \
  --output /tmp/preview-capture.png
```

### Dynamic Preview Injection (Xcode Projects)

Fast builds by injecting a minimal PreviewHost target:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-dynamic.sh \
  <path-to-file.swift> \
  --project <path.xcodeproj> \
  --output /tmp/preview.png
```

### SPM Package Preview

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-spm.sh \
  <path-to-file.swift> \
  --output /tmp/preview.png
```

### Standalone Swift File

Build a standalone Swift file with system frameworks only:

```bash
"${PREVIEW_BUILD_PATH:-$HOME/Claude-XcodePreviews}"/scripts/preview-minimal.sh \
  <path-to-file.swift> \
  --output /tmp/preview.png
```

## Workflow

When the user asks to preview a SwiftUI view:

1. **Identify the target**: Determine what needs to be previewed (Swift file, project scheme, or current simulator state)

2. **Build and capture**: Run the appropriate script

3. **Read and analyze**: Use the Read tool to view the captured PNG at `/tmp/preview.png`

4. **Report findings**:
   - **Layout**: Structure and arrangement
   - **Visual elements**: Buttons, text, images
   - **Styling**: Colors, fonts, spacing
   - **Issues**: Alignment, overflow, accessibility
   - **Suggestions**: Improvements

## Parameters

| Option | Description |
|--------|-------------|
| `--project <path>` | Xcode project file |
| `--workspace <path>` | Xcode workspace file |
| `--package <path>` | SPM Package.swift path |
| `--module <name>` | Target module (auto-detected) |
| `--simulator <name>` | Simulator name (default: iPhone 17 Pro) |
| `--output <path>` | Output screenshot path |
| `--verbose` | Show detailed build output |

## Error Handling

- **No simulator booted**: Run `sim-manager.sh boot "iPhone 17 Pro"`
- **Build failure**: Show error, suggest fixes, offer to retry
- **Resource bundle crash**: The dynamic script auto-includes Tuist and common bundle patterns
- **Missing imports**: Check if the target module needs to be added to imports
