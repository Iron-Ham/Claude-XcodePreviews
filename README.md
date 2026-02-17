# PreviewBuild - SwiftUI Preview Capture Toolkit

A CLI toolset for building and capturing SwiftUI previews programmatically. Designed to work with AI coding assistants (Claude Code and Cursor) for visual analysis of UI components.

## Features

- **Dynamic Preview Injection** - Creates minimal PreviewHost targets instead of building full apps
- **SPM Package Support** - Works with standalone Swift packages
- **Xcode Project Support** - Works with xcodeproj files (including Tuist-generated projects)
- **Fast Builds** - Only builds required modules (~3-4 seconds for cached builds)
- **Resource Bundle Detection** - Automatically includes asset bundles for themes/colors

## Requirements

- macOS with Xcode installed
- iOS Simulator
- Ruby (comes with macOS) with `xcodeproj` gem

## Installation

### Prerequisites

```bash
gem install xcodeproj --user-install
```

### Claude Code: Plugin Marketplace (Recommended)

Install via the Claude Code plugin marketplace:

```
/plugin marketplace add Iron-Ham/Claude-XcodePreviews
/plugin install preview-build@Claude-XcodePreviews
```

### Claude Code: Manual Install

#### 1. Clone the repository

```bash
git clone https://github.com/Iron-Ham/Claude-XcodePreviews.git ~/Claude-XcodePreviews
```

#### 2. Install the Claude Code skill

Copy the skill definition to your user-level commands directory:

```bash
mkdir -p ~/.claude/commands
cp ~/Claude-XcodePreviews/.claude/commands/preview.md ~/.claude/commands/
```

> **Note:** The manual install expects scripts at `~/Claude-XcodePreviews`. If you cloned to a different location, create a symlink:
> ```bash
> ln -s /path/to/Claude-XcodePreviews ~/Claude-XcodePreviews
> ```

### Cursor: Install

#### 1. Clone the repository

```bash
git clone https://github.com/Iron-Ham/Claude-XcodePreviews.git ~/Claude-XcodePreviews
```

#### 2. Install the Cursor skill

Copy the skill to your user-level skills directory:

```bash
mkdir -p ~/.cursor/skills/preview
cp ~/Claude-XcodePreviews/.cursor/skills/preview/SKILL.md ~/.cursor/skills/preview/
```

#### 3. (Optional) Install the workspace rule

If you want the preview toolkit context always available in a specific project, copy the rule to that project's `.cursor/rules/` directory:

```bash
mkdir -p /path/to/your/project/.cursor/rules
cp ~/Claude-XcodePreviews/.cursor/rules/preview.mdc /path/to/your/project/.cursor/rules/
```

> **Note:** Like the Claude Code install, this expects scripts at `~/Claude-XcodePreviews`. Set `PREVIEW_BUILD_PATH` to override:
> ```bash
> export PREVIEW_BUILD_PATH=/path/to/Claude-XcodePreviews
> ```

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

## AI Assistant Integration

### Claude Code

After installation, use the `/preview` command:

```
/preview path/to/MyView.swift
```

### Cursor

After installing the skill, ask the agent to preview a SwiftUI view:

```
Preview the file path/to/MyView.swift
```

In both cases, the assistant will:
1. Build the preview using the appropriate method
2. Capture a screenshot
3. Analyze and describe the visual output

## Scripts

| Script | Purpose |
|--------|---------|
| `preview` | Unified entry point |
| `preview-dynamic.sh` | Xcode project preview injection |
| `preview-spm.sh` | SPM package preview |
| `preview-minimal.sh` | Standalone files |
| `capture-simulator.sh` | Screenshot capture |
| `sim-manager.sh` | Simulator utilities |

## Project Structure

```
Claude-XcodePreviews/
├── .claude/                        # Claude Code integration
│   ├── commands/
│   │   └── preview.md              #   Slash command
│   └── settings.json               #   Project permissions
├── .claude-plugin/                 # Claude Code plugin marketplace
│   ├── marketplace.json
│   └── plugin.json
├── .cursor/                        # Cursor integration
│   ├── rules/
│   │   └── preview.mdc             #   Workspace rule
│   └── skills/
│       └── preview/
│           └── SKILL.md            #   Cursor skill definition
├── skills/
│   └── preview/
│       └── SKILL.md                # Claude Code plugin skill
├── scripts/
│   ├── preview                     # Unified entry point
│   ├── preview-dynamic.sh          # Xcode project injection
│   ├── preview-spm.sh              # SPM package preview
│   ├── preview-minimal.sh          # Standalone files
│   ├── capture-simulator.sh
│   └── sim-manager.sh
└── templates/
```

## License

MIT
