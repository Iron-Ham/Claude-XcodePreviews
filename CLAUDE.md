# PreviewBuild - SwiftUI Preview Capture Toolkit

A toolkit for building and capturing SwiftUI previews for visual analysis.

## Quick Start

```bash
# Standalone Swift file (no external dependencies)
./scripts/preview MyView.swift

# File in an Xcode project (auto-injects PreviewHost target)
./scripts/preview ContentView.swift --project MyApp.xcodeproj

# File in an SPM package
./scripts/preview Sources/Module/MyView.swift

# Just capture current simulator
./scripts/preview --capture-only
```

## How It Works

### Project Types & Approaches

| Project Type | Approach | Build Time | Script |
|--------------|----------|------------|--------|
| **Standalone Swift** | Minimal host app | ~5 seconds | `preview-minimal.sh` |
| **Xcode project** | Dynamic target injection | ~3-4 seconds | `preview-tool` |
| **SPM package** | Temporary project creation | ~20 seconds | `preview-tool` |

### Dynamic Preview Injection

For Xcode projects, the toolkit:
1. Parses the Swift file to extract `#Preview { }` content
2. Injects a temporary `PreviewHost` target into the project
3. Configures dependencies based on imports
4. Detects and includes resource bundles (Tuist, standard naming)
5. Builds only the required modules
6. Captures screenshot
7. Cleans up the injected target

This is much faster than building a full app scheme.

## Scripts & Tools

| Path | Purpose |
|------|---------|
| `scripts/preview` | Unified entry point - auto-detects best approach |
| `scripts/preview-minimal.sh` | Build standalone Swift files |
| `scripts/xcode-preview.sh` | Build full Xcode project schemes |
| `scripts/capture-simulator.sh` | Screenshot current simulator |
| `scripts/sim-manager.sh` | Simulator management |
| `tools/preview-tool` | Swift CLI for dynamic preview injection, SPM preview, dependency resolution |

## Usage Examples

### Standalone Swift File

```bash
./scripts/preview templates/StandalonePreview.swift
```

### Xcode Project with #Preview

```bash
./scripts/preview Modules/Components/Chip/Chip.swift \
  --project MyApp.xcodeproj
```

### SPM Package

```bash
./scripts/preview Sources/IronPrimitives/Button/IronButton.swift
```

### Specific Options

```bash
./scripts/preview MyView.swift \
  --output ~/Desktop/preview.png \
  --simulator "iPhone 16 Pro" \
  --verbose
```

## Requirements

- macOS with Xcode installed
- iOS Simulator
- Swift toolchain (preview-tool auto-builds on first run)

## Workflow for Claude

When asked to preview a SwiftUI view:

1. **Run the preview script**:
   ```bash
   ./scripts/preview path/to/MyView.swift --output /tmp/preview.png
   ```

2. **View the screenshot**:
   ```
   Read /tmp/preview.png
   ```

3. **Analyze and report**: Describe layout, styling, colors, and any issues

## Skill Integration

The `/preview` skill is defined in `.claude/commands/preview.md` for use with Claude Code.
