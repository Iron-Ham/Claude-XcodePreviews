---
name: xcode-preview-capture
description: Build and capture SwiftUI previews for visual analysis in Codex. Use when asked to preview a Swift file, capture simulator UI, or inspect visual output from SwiftUI views.
---

# Xcode Preview Capture (Codex)

Use this skill to build SwiftUI previews and inspect screenshots.

## Prerequisites

- Xcode + iOS Simulator installed
- Ruby gem dependency:

```bash
gem install xcodeproj --user-install
```
- `PREVIEW_BUILD_PATH` set to this repository root
  - Example: `export PREVIEW_BUILD_PATH=/absolute/path/to/Claude-XcodePreviews`

## Primary Command

Use the unified entry point first:

```bash
"${PREVIEW_BUILD_PATH}"/scripts/preview \
  "<path-to-file.swift>" \
  --output /tmp/preview.png
```

The script auto-detects:
- Xcode project with `#Preview` -> dynamic target injection
- Swift Package -> SPM preview workflow
- Standalone Swift file -> minimal host build

## Capture Current Simulator

```bash
"${PREVIEW_BUILD_PATH}"/scripts/preview \
  --capture \
  --output /tmp/preview.png
```

## Workflow

1. Run `scripts/preview` with the requested file or `--capture`.
2. Confirm the output path exists.
3. Open `/tmp/preview*.png` and analyze the rendered UI.
4. Report structure, styling, and visible issues (alignment, clipping, contrast, etc.).

## Troubleshooting

- No simulator booted: run `sim-manager.sh boot "iPhone 17 Pro"`.
- Build failure: surface the error and suggest targeted fixes.
- Wrong project detected: pass `--project` or `--workspace` explicitly.
