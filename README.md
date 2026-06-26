# ClaudeMonitor

macOS menu-bar app that tracks Claude Code and OpenAI Codex token usage in real time.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-1.1.3-green)

## Features

- **Menu-bar live stats** — 5-hour rolling window and weekly usage displayed as water-tank gauges
- **Token rate indicator** — stacked bar gauge shows current throughput (idle → moderate → heavy → burst)
- **Claude Code HUD** — registers itself as a `statusLine` provider; renders model, action, context %, rate-limit bars, git branch, active tool, and cost directly in the Claude Code prompt
- **Codex support** — reads `~/.codex` session archives and shows today / weekly token counts alongside Claude
- **Dashboard window** — session list, daily/weekly charts, per-project breakdown for both Claude and Codex
- **Real-time file watching** — FSEvent-based, picks up new JSONL records the moment Claude Code writes them
- **`cm-status` CLI** — headless SQLite query for 5-hour / today / weekly token counts (plain text or JSON)
- **Multi-profile** — switch between different Claude accounts; each profile gets its own SQLite database
- **Auto HUD discovery** — transparently reads existing OMC / third-party HUD caches so no re-configuration is needed when another tool already provides data

## Requirements

- macOS 13 Ventura or later
- Xcode 15 (for building from source)

## Installation

Download the latest `ClaudeMonitor-x.x.x.dmg` from [Releases](../../releases), open it, and drag **ClaudeMonitor** into Applications.

On first launch the app:
1. Appears in the menu bar
2. Silently registers itself as the Claude Code `statusLine` provider (only if the slot is empty)
3. Starts scanning `~/.claude/projects` for existing session records

## Building from Source

```bash
git clone https://github.com/xivic/claude-monitor.git
cd claude-monitor
xcodegen generate          # requires: brew install xcodegen
open ClaudeMonitor.xcodeproj
```

Build and run the `ClaudeMonitor` scheme in Xcode, or:

```bash
xcodebuild -scheme ClaudeMonitor -configuration Release build
```

## Menu Bar

Click the icon to open the popover:

| Element | Description |
|---------|-------------|
| Water tank (5h window) | Remaining capacity in the current 5-hour rate-limit window |
| Water tank (weekly) | Remaining capacity for the 7-day period |
| Stacked bar gauge | Real-time token rate: green → orange → red |
| Reset timer | Countdown to next window/weekly reset |
| Codex bar | 5-hour usage % and today/weekly token count (when Codex is active) |

Color coding applies to both tanks and the menu-bar icon:
- **Green** ≥ 50 % remaining
- **Orange** 20–50 % remaining
- **Red** < 20 % remaining

## Claude Code HUD

The app writes `~/.claudemonitor/hud.sh` and registers it in `~/.claude/settings.json` as `statusLine`. Each time Claude Code renders the prompt, the script:

1. Pipes the session JSON into `~/.claudemonitor/hud-cache.json` (the menu-bar app reads this)
2. Renders a one-line status via `hud-render.mjs`:

```
🔹 CC 1.x  🧠 claude-opus-4  ▶️ running  📊 ctx 42%  ⏱️ 5h 28%  📅 wk 15%  🌿 git main  💰 $0.12
```

Configure which fields appear and the display style (emoji on/off, filled/outline, single/multiline) in **Settings → Claude → HUD Display**.

If another tool (e.g. OMC) already occupies the `statusLine`, ClaudeMonitor chains behind it so both coexist.

## `cm-status` CLI

Copy `scripts/cm-status` to somewhere on your `$PATH`:

```bash
cp scripts/cm-status /usr/local/bin/cm-status
chmod +x /usr/local/bin/cm-status
```

Usage:

```bash
cm-status           # plain-text summary
cm-status --json    # JSON (pipe-friendly)
```

Example output:

```
5h  window :    142381 tokens
This week  :    891204 tokens
Today      :    203455 tokens  ($0.8821)
```

The app keeps `~/Library/Application Support/ClaudeMonitor/active.sqlite` as a stable symlink to the current profile's database, so external scripts can always query the same path.

## Settings

| Tab | Option |
|-----|--------|
| Claude | Toggle Claude monitoring on/off |
| Claude | HUD connection — register, unregister, or chain with existing HUD |
| Claude | HUD display fields and style |
| Codex | Toggle Codex monitoring on/off |
| Codex | Custom `~/.codex` home path |

## Architecture

```
~/.claude/projects/**/*.jsonl   (Claude Code writes)
         │
         ▼ FSEventWatcher
    JSONLParser → SQLiteStore (GRDB)
         │
         ▼ Combine publishers
    AppState → SwiftUI views (MenuBarView, DashboardView)

~/.claudemonitor/hud-cache.json (Claude Code CLI writes via hud.sh)
         │
         ▼ file-descriptor watcher
    AnthropicUsageReader → rate-limit overlays
```

See [`docs/diagrams/`](docs/diagrams/) for PlantUML architecture, data-flow, and schema diagrams.

## License

MIT
