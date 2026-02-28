#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPECTED_BRANCH="lightweight-fetch"
BRANCH="$(git branch --show-current)"

if [[ "$BRANCH" != "$EXPECTED_BRANCH" ]]; then
  echo "ERROR: expected branch '$EXPECTED_BRANCH', got '$BRANCH'."
  echo "Run: git checkout $EXPECTED_BRANCH"
  exit 1
fi

if ! command -v xcode-select >/dev/null 2>&1; then
  echo "ERROR: xcode-select not found"
  exit 1
fi

if ! xcode-select --version >/dev/null 2>&1; then
  echo "ERROR: Xcode Command Line Tools are not installed"
  echo "Run: xcode-select --install"
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: swift not found"
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI not found"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude CLI not found"
  exit 1
fi

if [[ ! -f "$HOME/.codex/auth.json" ]]; then
  echo "ERROR: missing Codex auth file: $HOME/.codex/auth.json"
  echo "Run: codex login"
  exit 1
fi

if [[ ! -d "$HOME/.claude" ]]; then
  echo "ERROR: missing Claude config directory: $HOME/.claude"
  echo "Run: claude login"
  exit 1
fi

if pgrep -x "MeterBar" >/dev/null; then
  echo "ERROR: MeterBar is running. Uninstall it before installing CodexBar Lite."
  echo "Run: brew uninstall --cask meterbar"
  exit 1
fi

if [[ -d "/Applications/MeterBar.app" ]]; then
  echo "ERROR: /Applications/MeterBar.app is installed. Remove it before installing CodexBar Lite."
  echo "Run: brew uninstall --cask meterbar"
  exit 1
fi

echo "Building CodexBar Lite..."
CODEXBAR_SIGNING=adhoc "$ROOT/Scripts/package_app.sh"

if pgrep -x "CodexBar" >/dev/null; then
  echo "Stopping running CodexBar instance..."
  osascript -e 'quit app "CodexBar"' || true
  sleep 1
fi

echo "Installing /Applications/CodexBar.app ..."
rm -rf /Applications/CodexBar.app
cp -R "$ROOT/CodexBar.app" /Applications/CodexBar.app

open /Applications/CodexBar.app

CLI_HELPER="/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"

if [[ ! -x "$CLI_HELPER" ]]; then
  echo "ERROR: missing CLI helper at $CLI_HELPER"
  exit 1
fi

echo "Running post-install health checks..."
if ! "$CLI_HELPER" usage --provider codex --source oauth --json-only >/dev/null; then
  echo "ERROR: Codex health check failed."
  echo "Run: codex login"
  exit 1
fi

if ! "$CLI_HELPER" usage --provider claude --source oauth --json-only >/dev/null; then
  echo "ERROR: Claude health check failed."
  echo "Run: claude login"
  exit 1
fi

echo "Done. CodexBar Lite launched and health checks passed."
