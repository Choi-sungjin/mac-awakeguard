# mac-awakeguard

**mac-awakeguard** is a small, safe macOS menu bar utility that keeps your Mac awake during local work sessions.

Use it when local servers, background jobs, AI agents, downloads, or development tools should keep running while the display sleeps or the screen is locked.

> Safety boundary: mac-awakeguard prevents **idle sleep**. It does **not** bypass macOS hardware safety behavior, closed-lid battery sleep, clamshell requirements, or thermal protections.

## When to use it

Use mac-awakeguard when your Mac is in a safe working condition and you want to temporarily prevent idle sleep.

Good use cases:

- Keep a local development server available during a long task.
- Keep localhost tools such as Hermes Gateway, Paperclip, databases, dashboards, or dev servers reachable.
- Run local AI agents, build jobs, downloads, or scripts without idle sleep interrupting them.
- Keep work running while the display is off or the screen is locked.
- Start a timed awake session, such as 1 hour, 2 hours, or a full work block.

Do **not** use it as a promise that a MacBook will keep running with the lid closed on battery power.

Not supported / not recommended:

- Keeping a closed MacBook awake inside a bag.
- Bypassing macOS clamshell mode requirements.
- Disabling SIP, kernel protections, or system-wide power settings.
- Overriding thermal, battery, or hardware safety behavior.

## Features

- Menu bar app with no Dock icon.
- Timed awake sessions from 1 to 25 hours.
- Infinite mode until manually disabled.
- Gateway Guard mode for checking local Hermes Gateway / Paperclip status.
- Manual health check.
- Quick access to logs and the bundled usage guide.
- Conservative safety warnings around closed-lid and battery-related limitations.

## Install from a release build

1. Go to the repository's **Releases** page.
2. Download the latest `mac-awakeguard.app.zip` asset.
3. Unzip the file.
4. Move the `.app` into your Applications folder:
   - recommended for one user: `~/Applications/`
   - system-wide: `/Applications/`
5. Open the app from Finder.

If macOS blocks the app because it is downloaded from the internet or locally signed:

1. Open **System Settings** → **Privacy & Security**.
2. Find the blocked app message.
3. Click **Open Anyway**.

You can also remove quarantine from Terminal after moving the app:

```bash
xattr -dr com.apple.quarantine ~/Applications/HeraAwakeGuard.app
open ~/Applications/HeraAwakeGuard.app
```

If you moved it to `/Applications`, use:

```bash
xattr -dr com.apple.quarantine /Applications/HeraAwakeGuard.app
open /Applications/HeraAwakeGuard.app
```

## Build from source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift compiler

Install Xcode Command Line Tools if needed:

```bash
xcode-select --install
```

Clone, build, and install for the current user:

```bash
git clone https://github.com/Choi-sungjin/mac-awakeguard.git
cd mac-awakeguard
./scripts/build_and_install.sh
open ~/Applications/HeraAwakeGuard.app
```

The build script installs the app to:

```text
~/Applications/HeraAwakeGuard.app
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
- **Gateway Guard**: keeps the Mac awake and checks local Hermes Gateway / Paperclip health.
- **Run health check**: checks the current local service state immediately.
- **Open logs**: opens the local app log.
- **Open usage**: opens the bundled HTML usage guide.

## Verify that it is working

Start an awake session from the menu, then run:

```bash
pmset -g assertions | grep -i "Awake Guard"
```

When mac-awakeguard is active, you should see a power assertion created by the app.

From a source checkout, you can also run:

```bash
./scripts/qa_smoke.sh
```

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

Build and install locally:

```bash
./scripts/build_and_install.sh
```

Run the installed app:

```bash
open ~/Applications/HeraAwakeGuard.app
```

Smoke test:

```bash
./scripts/qa_smoke.sh
```

Package a release zip:

```bash
./scripts/build_and_install.sh
cd ~/Applications
ditto -c -k --keepParent HeraAwakeGuard.app ~/Desktop/mac-awakeguard.app.zip
shasum -a 256 ~/Desktop/mac-awakeguard.app.zip
```

## License

MIT
