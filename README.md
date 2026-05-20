# mac-awakeguard

**mac-awakeguard** is a small macOS menu bar utility for one core goal: keep your local gateway reachable while the Mac is awake, locked, display-asleep, or left running for local work.

It starts in **Gateway Guard** mode by default. That mode keeps a macOS awake assertion active and checks local Hermes Gateway / Paperclip health. It cannot guarantee Telegram/Gateway calls while a MacBook is in closed-lid **Clamshell Sleep**.

> Safety boundary: mac-awakeguard prevents **idle sleep** while macOS allows the user session to remain awake. It does **not** bypass closed-lid Clamshell Sleep, macOS hardware safety behavior, unsafe closed-lid battery sleep, clamshell requirements, or thermal protections.

## When to use it

Use mac-awakeguard when your Mac is in a safe working condition and you want to temporarily prevent idle sleep.

Good use cases:

- Keep a local development server available during a long task.
- Keep localhost tools such as Hermes Gateway, Paperclip, databases, dashboards, or dev servers reachable.
- Run local AI agents, build jobs, downloads, or scripts without idle sleep interrupting them.
- Keep work running while the display is off, the screen is locked, or the Mac is otherwise allowed to remain awake.
- Start Gateway Guard before a long local task so the gateway remains reachable when macOS allows the machine to stay awake.
- Start a timed awake session, such as 1 hour, 2 hours, or a full work block.

Do **not** use it as a promise that a MacBook will keep running with the lid closed on battery power.

Not supported / not recommended:

- Keeping a closed MacBook awake inside a bag.
- Bypassing macOS clamshell mode requirements.
- Disabling SIP, kernel protections, or system-wide power settings.
- Overriding thermal, battery, or hardware safety behavior.

## Closed-lid and Bluetooth reality

mac-awakeguard does **not** “hack around” clamshell sleep. It holds normal macOS power assertions, then reports when the machine appears to be in a risky closed-lid state.

The reliable closed-lid path is Apple's normal clamshell behavior:

- AC power is connected.
- An external display is connected.
- An external keyboard, mouse, or trackpad is available. These can be USB or Bluetooth.
- The Mac is on a desk with airflow.

Bluetooth matters only as part of that official external-input setup. A paired Bluetooth keyboard, mouse, or trackpad can help keep a legitimate clamshell session usable, but a Bluetooth device by itself is not a safe bypass for lid-closed battery sleep. If the lid is closed and macOS enters **Clamshell Sleep**, Telegram/Gateway calls can stop even though the app, Gateway, or Paperclip looked healthy before sleep.

Practical recommendation:

- Best: AC power + external display + Bluetooth/USB keyboard or mouse/trackpad + Gateway Guard.
- Acceptable: screen locked or display asleep with the cover open + Gateway Guard.
- Avoid: closed lid on battery, especially in a bag.

## Features

- Menu bar app with no Dock icon.
- Timed awake sessions from 1 to 25 hours.
- Infinite mode until manually disabled.
- Gateway Guard mode enabled by default at launch.
- Gateway Guard keeps awake assertions active and checks local Hermes Gateway / Paperclip status.
- Manual health check.
- Quick access to logs and the bundled usage guide.
- Conservative safety warnings around closed-lid, Bluetooth/clamshell assumptions, and battery-related limitations.

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

If you are building from an automation profile where `$HOME` is not the human user's home, set `INSTALL_HOME` explicitly:

```bash
INSTALL_HOME=/Users/yourname ./scripts/build_and_install.sh
open /Users/yourname/Applications/HeraAwakeGuard.app
```

The build script installs the app to:

```text
~/Applications/HeraAwakeGuard.app
```

## How to use

After opening the app, it appears in the macOS menu bar. It does not show a Dock icon.

Typical gateway flow:

1. Open the app. Gateway Guard starts automatically.
2. Confirm the menu bar icon is green or shows Gateway Guard.
3. Leave your Mac in a safe condition: on a desk, with airflow, preferably connected to power.
4. Close the cover only in a safe setup. For clamshell use, prefer AC power + external display + Bluetooth/USB keyboard or mouse/trackpad.
5. When finished, choose `Disable` or quit the app.

For a simple timed session instead of gateway monitoring, choose a duration such as `1 hour`, `2 hours`, or another timed session from the menu.

Useful modes:

- **Timed session**: keeps the Mac awake for a selected number of hours.
- **Infinite**: keeps the Mac awake until you manually turn it off.
- **Gateway Guard**: default mode. Keeps the Mac awake and checks local Hermes Gateway / Paperclip health so gateway access can survive cover-close conditions when macOS permits it.
- **Run health check**: checks the current local service state immediately.
- **Open logs**: opens the local app log.
- **Open usage**: opens the bundled HTML usage guide.

## Verify that it is working

Open the app or start Gateway Guard from the menu, then run:

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

- guarantee closed-lid battery operation in unsafe or thermally constrained conditions
- bypass thermal protections
- change global `pmset` settings
- install kernel extensions
- require SIP to be disabled

Recommended long-running setup:

- Keep the Mac on a desk with airflow.
- Connect power for long sessions.
- For the strongest closed-cover gateway reliability, keep AC power connected.
- Official clamshell conditions remain the safest closed-lid path: AC power, external display, and an external keyboard/mouse/trackpad. The input device may be Bluetooth or USB.
- Do not treat “Bluetooth connected” alone as a bypass. Without AC power and external display, macOS may still enter Clamshell Sleep.
- Battery + closed cover + bag is not a safe target for gateway uptime.

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
