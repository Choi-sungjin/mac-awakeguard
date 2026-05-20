#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_HOME="${INSTALL_HOME:-$HOME}"
APP_BUNDLE="$INSTALL_HOME/Applications/HeraAwakeGuard.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/HeraAwakeGuard"
ASSERTION_NAME="Hera Awake Guard - QA Smoke"

"$PROJECT_ROOT/scripts/build_and_install.sh" >/dev/null

echo "[1/5] LSUIElement check"
plutil -extract LSUIElement raw -o - "$APP_BUNDLE/Contents/Info.plist"

echo "[2/5] Headless assertion smoke"
"$APP_BIN" --assert-seconds 12 >/tmp/hera-awake-guard-assert.log 2>&1 &
ASSERT_PID=$!
sleep 2
pmset -g assertions | rg "$ASSERTION_NAME"
wait "$ASSERT_PID"

echo "[3/5] Assertion released"
if pmset -g assertions | rg -q "$ASSERTION_NAME"; then
  echo "Assertion still present after smoke run" >&2
  exit 1
fi

echo "[4/5] launchd health"
launchctl print "gui/$(id -u)/ai.hermes.gateway-hera" | rg "state = running"
launchctl print "gui/$(id -u)/ai.paperclip.default" | rg "state = running"

echo "[5/5] Paperclip and app health"
curl -fsS http://127.0.0.1:3100/api/health
"$APP_BIN" --health-check
