# Xcode Preview Capture Skill

<skill-definition>
name: preview
description: Build and capture Xcode/SwiftUI previews for visual analysis
invocation: /preview
</skill-definition>

## Overview

This skill allows you to build SwiftUI views and capture screenshots of their rendered output for visual analysis. It supports:

- Building standalone Swift files containing SwiftUI views
- Building views from existing Xcode projects
- Building views from SPM packages
- Capturing the current simulator screen
- Analyzing the captured screenshots

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
Capture a screenshot of whatever is currently displayed on the booted simulator.

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
For files in Swift Package Manager packages:

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

When the user invokes `/preview`, follow this workflow:

1. **Identify the target**: Determine what needs to be previewed:
   - A specific Swift file
   - An Xcode project/workspace with a scheme
   - The current simulator state

2. **Build and capture**: Use the appropriate script based on the target

3. **Read and analyze**: Use the Read tool to view the captured PNG image

4. **Report findings**: Describe what you see in the preview, including:
   - Layout and structure
   - Colors and styling
   - Any potential issues (alignment, overflow, etc.)
   - Suggestions for improvement

## Parameters

The user can specify:
- `file`: Path to a Swift file to preview
- `project`: Path to an Xcode project
- `workspace`: Path to an Xcode workspace
- `scheme`: Build scheme name
- `simulator`: Simulator to use (default: "iPhone 17 Pro")
- `wait`: Seconds to wait before capture (default: 3)

## Example Usage

```
User: /preview ContentView.swift
User: /preview --project MyApp.xcodeproj --scheme MyApp
User: /preview --capture-only
```

## Error Handling

If the build fails:
1. Show the build error output
2. Suggest fixes based on the error messages
3. Offer to try again after fixes are applied

If no simulator is booted:
1. List available simulators
2. Offer to boot one

## Output

After capturing, always:
1. Confirm the screenshot was saved
2. Read the image using the Read tool
3. Provide analysis of what's visible
