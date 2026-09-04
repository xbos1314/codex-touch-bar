# Codex Touch Bar

![Codex Touch Bar hero image](assets/hero.png)

Languages: English | [简体中文](README.zh-CN.md)

Codex Touch Bar is a macOS menu bar app that mirrors the active Codex task onto the physical Touch Bar and, optionally, the menu bar itself. It shows the current Codex conversation, assistant replies, tool activity, approval waits, completion state, and a compact file reading mode.

The Touch Bar experience is designed for MacBook Pro models with a physical Touch Bar, such as the 13-inch MacBook Pro M2. Macs without a Touch Bar can use the optional menu bar content display. The app runs as a menu bar app and does not show a Dock icon.

## Screenshots

### Running

![Codex task running on the Touch Bar](assets/screenshots/task_run.png)

### Waiting for Approval

![Codex approval request on the Touch Bar](assets/screenshots/task_approval.png)

### Completed

![Completed Codex task on the Touch Bar](assets/screenshots/task_complete.png)

### Idle

![Idle Codex Touch Bar pet](assets/screenshots/task_idle.png)

## Features

- Codex session display: reads local Codex JSONL session files under `~/.codex/sessions` and shows the latest user message, assistant reply, and tool activity.
- Automatic following: `AUTO` mode follows the most recently active primary Codex session.
- Manual session lock: tap the left Touch Bar pet entry to open the session selector and lock the display to a specific session. The selector supports horizontal swiping; the menu bar also provides `AUTO` plus the 10 most recently active sessions.
- Status pet: a minimal robot pet represents idle, running, approval wait, completed, failed, and reading states.
- Detail display: supports both scrolling and paging modes, with independent speed controls for each. User interaction pauses automatic scrolling or paging for the current message; automatic behavior resumes when a new message appears.
- Menu bar content: optionally shows the current detail text alongside a compact colored status icon. Long content automatically pages in place with its own speed control; clicking still opens the standard app menu.
- Approval display: pending Codex tool approvals are shown directly on the Touch Bar, with a distinct approval pet color.
- Open current session: available from both the menu bar and the right side of the Touch Bar.
- Manual idle: after completion, the idle action can dismiss the completed state and return to an idle message.
- Idle interaction: tap the pet to open the session selector, or tap its free movement area to place a colored marker. The pet walks to and consumes markers in order with a blink-and-hop animation, retaining the color of the last marker it consumes; up to five markers can be present at once.
- Completion sound: plays a short local sound when a task completes.
- Completion speech: can automatically read the final assistant reply aloud. The menu bar exposes enablement, voice selection, speech rate, and pitch controls.
- Reading mode: open local text files for a night-reading style Touch Bar view or automatic menu bar reader. Opening a file switches menu bar content to the document and enables it automatically. It supports TXT, Markdown, Word documents, and common source code files.
- Reading progress: on a physical Touch Bar, remembers the latest file and page, supports continue reading, auto-page speed settings, and paragraph navigation. Menu bar reading uses its independent status bar paging speed.

## Touch Bar Layout

Codex session mode:

```text
Pet/session entry | Detail content | Open current session | Idle
```

Reading mode:

```text
Auto page | Previous page | Detail content | Next page | Paragraph selector
```

Idle messages:

- `AUTO · 暂无进行中的任务`
- `<Project name> · 暂无进行中的任务`

## Menu Bar

The menu is grouped by purpose:

- Codex session: current session, project, a session-switching submenu with `AUTO` and the 10 most recent sessions, open current session, completion speech, voice, rate, and pitch.
- Reading: current file, path, progress, open file, continue reading, and auto-page speed. Exit reading mode appears only while a file is open. This group remains available on Macs without a physical Touch Bar for menu bar reading.
- Touch Bar: on supported hardware, a fixed Control Strip entry, detail display mode, scrolling speed, and paging speed. This group is hidden when no physical Touch Bar is detected at launch.
- Menu Bar: optional current-detail display with a compact colored status icon, automatically pages long content, and exposes an independent paging speed.
- General: pause updates, refresh now, and quit.

## Agent Installation

An AI coding agent can install and launch the app from a fresh checkout with these steps:

```bash
git clone https://github.com/xbos1314/codex-touch-bar.git
cd codex-touch-bar
swift build
./scripts/package-app.sh
osascript -e 'tell application "Codex Touch Bar" to quit' 2>/dev/null || true
ditto "dist/Codex Touch Bar.app" "/Applications/Codex Touch Bar.app"
open "/Applications/Codex Touch Bar.app"
```

## Build and Run

The project uses SwiftPM:

```bash
swift build
```

Package the app bundle:

```bash
scripts/package-app.sh
open "dist/Codex Touch Bar.app"
```

Install it into `/Applications`:

```bash
ditto "dist/Codex Touch Bar.app" "/Applications/Codex Touch Bar.app"
open "/Applications/Codex Touch Bar.app"
```

Verify the generated app signature:

```bash
codesign --verify --deep --strict "dist/Codex Touch Bar.app"
```

## Project Layout

```text
Sources/CodexTouchBarApp/       macOS AppKit menu bar app and Touch Bar controller
Sources/CodexTouchBarCore/      Session parsing, state reduction, display policies, and settings
assets/screenshots/             README screenshots
Packaging/                      Info.plist and app icon source
scripts/package-app.sh          SwiftPM build and .app packaging script
```

## Known Limitations

- Codex content is read from local `~/.codex/sessions` JSONL files, so display updates can have a small delay.
- The always-on Control Strip entry depends on private macOS Touch Bar behavior and may need adjustment after macOS updates.
- The app displays and opens Codex sessions, but it does not send replies into Codex sessions.
- Physical Touch Bar behavior must be manually checked on the target MacBook Pro.
- Touch Bar hardware is detected from local IORegistry markers at launch. When it is unavailable, the app does not create or drive a Touch Bar and hides Touch Bar-only menu options.

## Development Notes

- Build the app bundle with `scripts/package-app.sh`.
- Main transcript cleanup lives in `Sources/CodexTouchBarCore/CodexDisplayTextFormatter.swift`.
- Markdown reading cleanup lives in `Sources/CodexTouchBarCore/ReadingMarkdownTextFormatter.swift`.
- Robot pet drawing policy lives in `Sources/CodexTouchBarCore/TouchBarRobotPetDrawingPolicy.swift`.

## License

MIT. See [LICENSE](LICENSE).
