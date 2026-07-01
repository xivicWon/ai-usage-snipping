# Claude Code Skills for ClaudeMonitor

## 📊 claude-monitor-update

Builds ClaudeMonitor from source, creates a distributable DMG, installs it, and launches the app.

### Installation

The skill is automatically available in this project. You can invoke it via:

```bash
/claude-monitor-update
```

Or use the shorthand:
```bash
pm /claude-monitor-update
```

### What It Does

1. **Verifies Prerequisites** — Checks for Xcode and XcodeGen installation
2. **Generates Project** — Creates Xcode project from `project.yml` (if needed)
3. **Builds Release Binary** — Compiles ClaudeMonitor with Release configuration
4. **Ad-hoc Code Signing** — Signs the app for local distribution (no Apple Developer account needed)
5. **Creates DMG** — Packages the app as a distributable disk image
6. **Installs to Applications** — Copies `ClaudeMonitor.app` to `/Applications`
7. **Launches** — Opens the app immediately after installation

### Requirements

- **macOS 13+** (Ventura or later)
- **Xcode 15+** — Install from App Store or `xcode-select --install`
- **XcodeGen** — Install with `brew install xcodegen`
- **Write permission** to `/Applications`
- **Disk space** — ~10GB for Xcode build artifacts

### Setup (One-time)

Before first use, ensure you have the required tools:

```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install XcodeGen via Homebrew
brew install xcodegen
```

### Usage Examples

**Build and launch ClaudeMonitor:**
```bash
/claude-monitor-update
```

**Run as a background task (if you have other work to do):**
```bash
pm /claude-monitor-update &
```

### Output

The skill provides colored progress output:
- ✓ **Green**: Successful steps
- ✗ **Red**: Errors or missing prerequisites
- ! **Yellow**: Step indicators (progress)
- ━ **Blue**: Section dividers

Example output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ClaudeMonitor Update & Launch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/4] Checking prerequisites...
✓ Prerequisites met

[2/4] Preparing Xcode project...
✓ Xcode project ready

[3/4] Building ClaudeMonitor...
✓ Build complete

[4/4] Installing to Applications...
✓ Installed to /Applications/ClaudeMonitor.app

Launching ClaudeMonitor...
✓ ClaudeMonitor is launching...
```

### Troubleshooting

**"Xcode is not installed"**
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Or install full Xcode from App Store
```

**"XcodeGen is not installed"**
```bash
brew install xcodegen
```

**Build fails with "Swift compiler error"**
- Ensure you have Xcode 15.0 or later: `xcode-select --install`
- Update macOS to 13+ (Ventura or later)
- Clean build artifacts and retry:
  ```bash
  rm -rf build/ DerivedData/
  /claude-monitor-update
  ```

**"Permission denied" when installing to /Applications**
- The app may already be running
- Close ClaudeMonitor first, then run the skill again
- Or install to a custom location:
  ```bash
  defaults write com.example.ClaudeMonitor InstallPath "$HOME/Applications"
  ```

**DMG won't unmount**
- The app was just launched and may still be initializing
- Wait a few seconds, then manually eject: `open ~/.Trash` and empty trash

### Build Artifacts

After running the skill, build artifacts are stored in:
```
./build/          — Xcode build output and derived data
./ClaudeMonitor-*.dmg  — Distributable disk image (can be shared)
```

To clean up old build artifacts:
```bash
rm -rf ./build/ ./ClaudeMonitor-*.dmg
```

### Manual Build (Alternative)

If you prefer to build manually without the skill:

```bash
# Navigate to project directory
cd /Users/wonjaeho/Workspace/claude-monitor

# Generate Xcode project (one-time)
xcodegen generate

# Build using the build script
./scripts/build-dmg.sh

# Install manually
hdiutil attach ClaudeMonitor-1.4.1.dmg
cp -r /Volumes/ClaudeMonitor/ClaudeMonitor.app /Applications/
hdiutil detach /Volumes/ClaudeMonitor
open /Applications/ClaudeMonitor.app
```

### Development

To modify the skill:
1. Edit `update-and-run-monitor.sh` for the installation logic
2. Edit `claude-monitor-update.yml` for skill metadata
3. Test with: `/claude-monitor-update`

### Files

- `update-and-run-monitor.sh` — Main installation script
- `claude-monitor-update.yml` — Skill definition and metadata
- `README.md` — This file

---

**Repository:** https://github.com/xivicWon/ai-usage-snipping  
**Version:** Latest from GitHub releases  
**License:** MIT
