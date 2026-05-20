# mac-awakeguard

**mac-awakeguard** is a small, safe macOS menu bar utility for keeping your Mac awake during local work sessions.

It is useful when you are running local services, background jobs, agent workflows, or development tools that should remain available while the display sleeps or the screen is locked.

> Safety boundary: mac-awakeguard does **not** bypass macOS hardware safety behavior, closed-lid battery sleep, clamshell requirements, or thermal protections.

## When to use it

Use mac-awakeguard when you want to temporarily prevent idle sleep while your Mac is in a safe working condition.

Good use cases:

- Keeping local development servers available during a long task.
- Keeping Hermes Gateway, Paperclip, or other localhost tools reachable.
- Running local AI agents, build jobs, downloads, or scripts without idle sleep interrupting them.
- Keeping a Mac awake while the display is off or the screen is locked.
- Running a timed awake session, such as 1 hour, 2 hours, or a full work block.

Do **not** use it as a promise that a MacBook will keep running with the lid closed on battery power.

Not supported / not recommended:

- Keeping a closed MacBook awake inside a bag.
- Bypassing macOS clamshell mode requirements.
- Disabling SIP, kernel protections, or system-wide power settings.
- Overriding thermal, battery, or hardware safety behavior.

## What it does

mac-awakeguard uses standard macOS IOKit power assertions to request that macOS avoid idle sleep for a selected duration.

Main features:

- Menu bar app with no Dock icon.
- Timed awake sessions from 1 to 25 hours.
- Infinite mode until manually disabled.
- Gateway Guard mode for checking Hermes Gateway and Paperclip status.
- Manual health check.
- Quick access to logs and usage guide.
- Safe warnings for closed-lid and battery-related limitations.

## Installation

### Option 1: Download a release build

1. Download the latest `mac-awakeguard.app.zip` from the GitHub Releases page.
2. Unzip it.
3. Move `mac-awakeguard.app` or `HeraAwakeGuard.app` to your `Applications` folder.
4. Open the app.

If macOS blocks the app because it is unsigned or locally signed:

1. Open **System Settings** → **Privacy & Security**.
2. Find the blocked app message.
3. Click **Open Anyway**.

Or run:

```bash
xattr -dr com.apple.quarantine /Applications/HeraAwakeGuard.app
open /Applications/HeraAwakeGuard.app
```

### Option 2: Build from source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift compiler

Build and install:

```bash
git clone https://github.com/Choi-sungjin/mac-awakeguard.git
cd mac-awakeguard
./scripts/build_and_install.sh
open /Users/sungjin/Applications/HeraAwakeGuard.app
```

Current local install path used by the build script:

```text
/Users/sungjin/Applications/HeraAwakeGuard.app
```

## How to use

After opening the app, it appears in the macOS menu bar. It does not show a Dock icon.

Typical flow:

1. Click the menu bar icon.
2. Choose a duration such as `1 hour`, `2 hours`, or another timed session.
3. Leave your Mac in a safe condition: on a desk, with airflow, preferably connected to power for long sessions.
4. When finished, choose `Disable` or quit the app.

Useful modes:

- **Timed session**: keeps the Mac awake for a selected number of hours.
- **Infinite**: keeps the Mac awake until you manually turn it off.
- **Gateway Guard**: keeps the Mac awake and checks Hermes Gateway / Paperclip health.
- **Run health check**: checks the current service state immediately.
- **Open logs**: opens the local app log.

## Verify that it is working

Run:

```bash
pmset -g assertions | grep -i "Awake Guard"
```

When mac-awakeguard is active, you should see a power assertion created by the app.

You can also run the smoke test from the source directory:

```bash
./scripts/qa_smoke.sh
```

The smoke test verifies:

- menu bar app configuration (`LSUIElement=true`)
- power assertion creation and release
- Hermes Gateway / Paperclip launchd status
- Paperclip health endpoint
- app-level health check

## Safety notes

mac-awakeguard is intentionally conservative.

It does not:

- force a MacBook to stay awake in unsafe closed-lid battery conditions
- bypass thermal protections
- change global `pmset` settings
- install kernel extensions
- require SIP to be disabled

Recommended long-running setup:

- Keep the Mac on a desk with airflow.
- Connect power for long sessions.
- Prefer lid open for the safest behavior.
- If using closed-lid mode, use official clamshell conditions: AC power, external display, keyboard, and mouse/trackpad.

## Development

Build:

```bash
./scripts/build_and_install.sh
```

Run:

```bash
open /Users/sungjin/Applications/HeraAwakeGuard.app
```

Smoke test:

```bash
./scripts/qa_smoke.sh
```

Package manually:

```bash
cd /Users/sungjin/Applications
ditto -c -k --keepParent HeraAwakeGuard.app ~/Desktop/mac-awakeguard.app.zip
shasum -a 256 ~/Desktop/mac-awakeguard.app.zip
```

## License

MIT
