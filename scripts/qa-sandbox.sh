#!/usr/bin/env bash
#
# qa-sandbox.sh — prove ClipTidy still works under the App Sandbox.
#
# The Mac App Store requires App Sandbox. This script builds the app, signs it
# ad-hoc WITH the real MAS entitlements, verifies the signature, launches it,
# and confirms macOS actually put it in a sandbox container. It needs no Apple
# certificates, so it runs today and de-risks the real submission.
#
# It does NOT replace the manual smoke test: copy messy text from a terminal,
# confirm auto-clean rewrites it. That needs a human at the keyboard.

set -euo pipefail

cd "$(dirname "$0")/.."

APP="ClipTidy"
BUNDLE="$APP.app"
BUNDLE_ID="com.cliptidy.app"
ENTITLEMENTS="Resources/ClipTidy.entitlements"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"

echo "==> Building and assembling $BUNDLE"
make app >/dev/null

echo "==> Ad-hoc signing with sandbox entitlements"
codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    "$BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "==> Confirming the sandbox entitlement is embedded"
if codesign -d --entitlements :- "$BUNDLE" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
    echo "    app-sandbox entitlement present"
else
    echo "    FAIL: app-sandbox entitlement missing" >&2
    exit 1
fi

echo "==> Launching sandboxed app to confirm it runs (3s)"
rm -rf "$CONTAINER"      # start clean so container creation is unambiguous
open "$BUNDLE"
sleep 3

if pgrep -x "$APP" >/dev/null; then
    echo "    process is alive under sandbox"
else
    echo "    FAIL: app exited or crashed on launch" >&2
    exit 1
fi

if [ -d "$CONTAINER" ]; then
    echo "    sandbox container created at $CONTAINER (sandbox is engaged)"
else
    echo "    FAIL: no sandbox container — app is NOT sandboxed" >&2
    pkill -x "$APP" 2>/dev/null || true
    exit 1
fi

echo "==> Quitting"
pkill -x "$APP" 2>/dev/null || true

echo ""
echo "PASS: ClipTidy builds, signs, and runs under the App Sandbox."
echo "Next, a human should smoke-test auto-clean from a terminal copy."
