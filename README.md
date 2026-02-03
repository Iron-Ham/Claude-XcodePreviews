# Claude XcodePreviews

A CLI toolset for building and capturing SwiftUI previews programmatically. Designed to work with Claude Code for visual analysis of UI components.

## Features

- **Dynamic Preview Injection** - Creates minimal PreviewHost targets instead of building full apps
- **SPM Package Support** - Works with standalone Swift packages
- **Xcode Project Support** - Works with xcodeproj files (including Tuist-generated projects)
- **Fast Builds** - Only builds required modules (~3-4 seconds for cached builds)
- **Resource Bundle Detection** - Automatically includes asset bundles for themes/colors

## Requirements

- macOS with Xcode installed
- iOS Simulator
- Ruby with `xcodeproj` gem: `gem install xcodeproj --user-install`
- Python 3 (for preview extraction)

## Installation

```bash
git clone https://github.com/Iron-Ham/Claude-XcodePreviews.git
cd Claude-XcodePreviews
```

## Usage

### Unified Entry Point

The `preview` script auto-detects the best approach:

```bash
# Preview a file in an Xcode project
./scripts/preview path/to/MyView.swift

# Preview a file in an SPM package
./scripts/preview path/to/Package/Sources/Module/MyView.swift

# Specify output path
./scripts/preview MyView.swift --output ~/Desktop/preview.png

# Capture current simulator
./scripts/preview --capture-only
```

### Direct Scripts

**For Xcode projects with `#Preview` blocks:**
```bash
./scripts/preview-dynamic.sh MyView.swift --project MyApp.xcodeproj
```

**For SPM packages:**
```bash
./scripts/preview-spm.sh MyView.swift --package /path/to/Package.swift
```

**For standalone Swift files (system imports only):**
```bash
./scripts/preview-minimal.sh MyView.swift
```

### Options

| Option | Description |
|--------|-------------|
| `--project <path>` | Xcode project file |
| `--workspace <path>` | Xcode workspace file |
| `--package <path>` | SPM Package.swift path |
| `--module <name>` | Target module (auto-detected) |
| `--simulator <name>` | Simulator name (default: iPhone 17 Pro) |
| `--output <path>` | Output screenshot path |
| `--verbose` | Show detailed build output |
| `--keep` | Keep temporary files after capture |

## How It Works

### For Xcode Projects

1. Parses the Swift file to extract `#Preview { }` content
2. Injects a temporary `PreviewHost` target into the project
3. Configures dependencies based on imports
4. Builds only the required modules
5. Launches in simulator and captures screenshot
6. Cleans up the injected target

### For SPM Packages

1. Creates a temporary Xcode project
2. Adds the local SPM package as a dependency
3. Generates a PreviewHost app with the preview content
4. Builds and captures screenshot

## Claude Code Integration

Add the skill to your Claude Code configuration:

```bash
cp -r .claude/commands/* ~/.claude/commands/
```

Then use `/preview path/to/file.swift` in Claude Code.

## Scripts

| Script | Purpose |
|--------|---------|
| `preview` | Unified entry point |
| `preview-dynamic.sh` | Xcode project preview injection |
| `preview-spm.sh` | SPM package preview |
| `preview-minimal.sh` | Standalone files |
| `capture-simulator.sh` | Screenshot capture |
| `sim-manager.sh` | Simulator utilities |

## License

MIT
