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
| **Xcode project** | Dynamic target injection | ~3-4 seconds | `preview-dynamic.sh` |
| **SPM package** | Temporary project creation | ~20 seconds | `preview-spm.sh` |

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

## Scripts

| Script | Purpose |
|--------|---------|
| `preview` | Unified entry point - auto-detects best approach |
| `preview-dynamic.sh` | Dynamic target injection for Xcode projects |
| `preview-spm.sh` | Preview from SPM packages |
| `preview-minimal.sh` | Build standalone Swift files |
| `xcode-preview.sh` | Build full Xcode project schemes |
| `capture-simulator.sh` | Screenshot current simulator |
| `sim-manager.sh` | Simulator management |

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
- Ruby with `xcodeproj` gem:
  ```bash
  gem install xcodeproj --user-install
  ```
- Python 3 (for preview extraction)

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
