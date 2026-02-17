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
- Swift toolchain (preview-tool auto-builds on first run)

## Installation

### Claude Code: Plugin Marketplace (Recommended)

Install via the Claude Code plugin marketplace:

```
/plugin marketplace add Iron-Ham/XcodePreviews
/plugin install preview-build@XcodePreviews
```

### Claude Code: Manual Install

#### 1. Clone the repository

```bash
git clone https://github.com/Iron-Ham/XcodePreviews.git ~/XcodePreviews
```

#### 2. Install the Claude Code skill

Copy the skill definition to your user-level commands directory:

```bash
mkdir -p ~/.claude/commands
cp ~/XcodePreviews/.claude/commands/preview.md ~/.claude/commands/
```

> **Note:** The manual install expects scripts at `~/XcodePreviews`. If you cloned to a different location, set `PREVIEW_BUILD_PATH`:
> ```bash
> export PREVIEW_BUILD_PATH=/path/to/XcodePreviews
> ```

> **Upgrading from `Claude-XcodePreviews`?** The old path `~/Claude-XcodePreviews` still works — the skill files fall back to it automatically. You can rename your clone at any time, or just leave it.

### Cursor: Install

#### 1. Clone the repository

```bash
git clone https://github.com/Iron-Ham/XcodePreviews.git ~/XcodePreviews
```

#### 2. Install the Cursor skill

Copy the skill to your user-level skills directory:

```bash
mkdir -p ~/.cursor/skills/preview
cp ~/XcodePreviews/.cursor/skills/preview/SKILL.md ~/.cursor/skills/preview/
```

#### 3. (Optional) Install the workspace rule

If you want the preview toolkit context always available in a specific project, copy the rule to that project's `.cursor/rules/` directory:

```bash
mkdir -p /path/to/your/project/.cursor/rules
cp ~/XcodePreviews/.cursor/rules/preview.mdc /path/to/your/project/.cursor/rules/
```

> **Note:** Like the Claude Code install, this expects scripts at `~/XcodePreviews`. Set `PREVIEW_BUILD_PATH` to override:
> ```bash
> export PREVIEW_BUILD_PATH=/path/to/XcodePreviews
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

## Codex Integration

Codex can use the same scripts through a Codex skill.

### Install Codex Skill

```bash
export PREVIEW_BUILD_PATH=/absolute/path/to/XcodePreviews
mkdir -p ~/.codex/skills/public/xcode-preview-capture
cp -R "$PREVIEW_BUILD_PATH"/.codex/skills/xcode-preview-capture/* \
  ~/.codex/skills/public/xcode-preview-capture/
```

Set `PREVIEW_BUILD_PATH` in your shell profile so Codex can invoke the scripts from any location.

### Use with Codex

Ask Codex to preview a SwiftUI file. The skill instructs Codex to:
1. Run `scripts/preview` with your target file
2. Capture `/tmp/preview*.png`
3. Read the screenshot and provide UI analysis

## Scripts & Tools

| Path | Purpose |
|------|---------|
| `scripts/preview` | Unified entry point (auto-detects best approach) |
| `scripts/preview-minimal.sh` | Standalone files (system imports only) |
| `scripts/capture-simulator.sh` | Screenshot capture |
| `scripts/sim-manager.sh` | Simulator utilities |
| `tools/preview-tool` | Swift CLI for dynamic preview injection + SPM preview |

## Project Structure

```
XcodePreviews/
├── .claude/                        # Claude Code integration
│   ├── commands/
│   │   └── preview.md              #   Slash command
│   └── settings.json               #   Project permissions
├── .claude-plugin/                 # Claude Code plugin marketplace
│   ├── marketplace.json
│   └── plugin.json
├── .codex/                         # Codex integration
│   └── skills/
│       └── xcode-preview-capture/
│           └── SKILL.md            #   Codex skill definition
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
│   ├── preview-minimal.sh          # Standalone files
│   ├── capture-simulator.sh
│   └── sim-manager.sh
├── tools/
│   └── preview-tool/               # Swift CLI (auto-built on first run)
│       ├── Package.swift
│       ├── Sources/
│       └── Tests/
└── templates/
```

## License

MIT
