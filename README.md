# ClaudeMonitor

A macOS menu-bar app that tracks your Claude Code and OpenAI Codex token usage in real time — and turns that activity into a **usage-pattern retrospective**: it quietly records how you work (without storing conversation text), then, on demand or on a schedule, has Claude look back and tell you what your habits actually look like.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![Version](https://img.shields.io/badge/version-1.4.1-green)

**English** · [한국어](README.ko.md)

---

## Features

- **Usage-pattern retrospective** — analyzes your real work sessions (bots/automation filtered out) and generates a look-back via headless `claude -p`; two styles: **standard** (a grounded coaching review) and **roast** (a brutally honest one). Manual "generate now" or automatic on a cadence, with a new-retro badge on the menu-bar icon. No API key needed — it reuses your logged-in Claude Code
- **Menu-bar live stats** — 5-hour rolling window and weekly usage displayed as water-tank gauges
- **Token rate indicator** — stacked bar gauge shows current throughput (idle → moderate → heavy → burst), with configurable thresholds (manual or auto-calculated)
- **Claude Code HUD** — registers itself as a `statusLine` provider; renders model, action, context %, rate-limit bars, git branch, active tool, reasoning effort, working directory, and cost directly in the Claude Code prompt
- **Customizable HUD layout** — drag-and-drop fields across rows, reorder chips within a row, and set a per-field color (auto or one of 8 presets); single- or multi-line styles
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

## Running with Xcode

**Prerequisites:** macOS 13+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml`, so you regenerate it after cloning or whenever files are added.

```bash
git clone https://github.com/xivicWon/ai-usage-snipping.git
cd ai-usage-snipping
xcodegen generate            # writes ClaudeMonitor.xcodeproj from project.yml
open ClaudeMonitor.xcodeproj
```

In Xcode:

1. Select the **ClaudeMonitor** scheme (top toolbar) and **My Mac** as the run destination.
2. Press **⌘R** (Product ▸ Run).
3. ClaudeMonitor is a **menu-bar (accessory) app — it has no Dock icon or window on launch.** Look for its icon in the **top-right menu bar**; click it for the popover, and use *Open Dashboard* for the retrospective/charts window.
4. To stop, press **⌘.** in Xcode (or *Quit* from the menu-bar popover).

Run the tests with **⌘U**, or from the command line:

```bash
xcodebuild test -scheme ClaudeMonitor -destination 'platform=macOS'
```

Build a release binary (ad-hoc signed) without opening Xcode:

```bash
xcodebuild -scheme ClaudeMonitor -configuration Release build
# or build a distributable .dmg:
./scripts/build-dmg.sh
```

> **Signing note:** releases are ad-hoc signed (no Apple Developer account). On first launch macOS Gatekeeper may block it — right-click the app ▸ **Open**, or run `xattr -dr com.apple.quarantine /Applications/ClaudeMonitor.app`. macOS system notifications also require proper signing, so the "new retrospective" alert is shown as a menu-bar badge instead.

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
🔹 CC 1.x  🧠 claude-opus-4  ▶️ running  🧩 effort high  📊 ctx 42%  ⏱️ 5h 28%  📅 wk 15%  🌿 git main  💰 $0.12
```

Available fields: CC version, model, action, session, folder (short), full path, context, 5h, weekly, git, tool, agent, cost, and reasoning effort. Customize the layout in **Settings → Claude → HUD Display**:

- **Drag-and-drop layout** — move fields between rows and reorder chips within a row
- **Per-field color** — `auto` (dynamic, value-driven) or one of 8 presets (blue, purple, green, yellow, cyan, orange, red, gray)
- **Display style** — emoji on/off, filled/outline bars, single- or multi-line

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

## Usage-Pattern Retrospective

The **🪞 Retrospective** tab in the Dashboard turns your recorded activity into a look-back on *how you actually use AI*.

- **What it uses** — small, derived per-session signals only (goals, tool mix, edited files, errors, mid-session interrupts, tokens, time-of-day). **Conversation text is never stored.** Bot/automation sessions (sub-agent orchestration, review bots, `.claude-brief` runs) are detected and excluded so the stats reflect *your* work.
- **How it generates** — the aggregated stats are sent through headless `claude -p` (your logged-in Claude Code — no API key, one call per run). Pick a period (1 day / 3 days / 7 days) and a style, then **Generate now**, or let it run on a schedule.
- **Two styles**
  - **Standard** — a grounded coaching review; every improvement point must cite a concrete number, no generic platitudes.
  - **Roast (갱생 회고)** — "roast me, based on everything you know about me," still grounded in your real numbers.
- **Where you see it** — read reports in the tab (Markdown), browse past ones in the history sidebar, and **Copy** any report to the clipboard. When a scheduled retrospective is ready, a green dot appears on the menu-bar icon and the *Retrospective* row until you open it.

Set the cadence in **Settings → 회고**: off / daily / every 3 days / weekly. Everything runs locally; nothing is uploaded.

## Settings

| Tab | Option |
|-----|--------|
| Claude | Toggle Claude monitoring on/off |
| Claude | HUD connection — register, unregister, or chain with existing HUD |
| Claude | HUD layout — drag-and-drop fields, per-field colors, single/multi-line style |
| Claude | Token-rate gauge thresholds (manual or auto-calculated) |
| Codex | Toggle Codex monitoring on/off |
| Codex | Custom `~/.codex` home path |
| 회고 | Retrospective cadence (off / daily / 3-day / weekly) + new-retro alert toggle |

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

# Retrospective pipeline
~/.claude/projects/**/*.jsonl
         │ ClaudeSessionFeatureParser  (text discarded, bots flagged)
         ▼
    SessionFeatureStore (features.sqlite)
         │ RetrospectiveAggregator (human sessions only)
         ▼
    RetrospectivePromptBuilder → claude -p → RetrospectiveReportStore
         ▲                                          │
    scheduler / "generate now"              Dashboard 회고 tab
```

See [`docs/diagrams/`](docs/diagrams/) for PlantUML architecture, data-flow, and schema diagrams.

## License

MIT
