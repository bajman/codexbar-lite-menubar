# CodexBar Lite

CodexBar Lite is a macOS menu bar app that keeps the CodexBar UI and UX, but enforces a low-overhead data path:

- providers: `codex`, `claude` only
- acquisition: local credentials + direct `URLSession` API calls
- no WebView scraping
- no browser cookie import/decryption
- no PTY/CLI/RPC probing

This repo is intended for users who want CodexBar’s interface without the heavy fallback pipeline.

## What You Get

- CodexBar menu bar UI, provider cards, and reset countdowns
- merge-icons mode (`codex`, `claude`, `combined`)
- WidgetKit widget (two-provider model)
- local cost usage display
- bundled helper CLI: `CodexBar.app/Contents/Helpers/CodexBarCLI`

## Lite Policy (Enforced)

- Allowed:
  - local credential read
  - direct API fetch through `URLSession`
- Forbidden:
  - WebView/dashboard scraping
  - browser cookie import/decryption
  - PTY probing
  - `codex ... app-server` probing
- Auth errors:
  - `401/403` returns explicit terminal guidance:
    - Codex: run `codex login`
    - Claude: run `claude login`
  - no fallback cascade and no silent refresh path in lite mode

## Credential Sources

- Codex: `~/.codex/auth.json`
- Claude: Keychain service `Claude Code-credentials` first, then `~/.claude` file fallback

## Quick Start

### 1. Requirements

- macOS 14+
- Xcode + command line tools
- authenticated `codex` and `claude` CLIs

### 2. Clone

```bash
git clone https://github.com/<your-user>/codexbar-lite-menubar.git
cd codexbar-lite-menubar
git checkout lightweight-fetch
```

### 3. Run setup

```bash
./Scripts/setup-lite.sh
```

`setup-lite.sh` does all of this:

- validates branch/toolchain/CLI auth files
- blocks install if MeterBar is installed or running
- builds and packages the app
- installs to `/Applications/CodexBar.app`
- launches the app
- runs helper CLI health checks for both providers

## Manual Build/Install

```bash
swift package resolve
swift build
swift test
CODEXBAR_SIGNING=adhoc ./Scripts/package_app.sh
cp -R CodexBar.app /Applications/CodexBar.app
open /Applications/CodexBar.app
```

## Operational Validation

Check provider fetches:

```bash
/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI usage --provider codex --source oauth --json-only
/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI usage --provider claude --source oauth --json-only
```

Idle performance checks:

```bash
pgrep -x CodexBar
ps -p "$(pgrep -x CodexBar)" -o %cpu=,rss=,command=
lsof -nP -a -p "$(pgrep -x CodexBar)" -i
```

Heavy-path regression checks:

```bash
rg -n "SweetCookieKit|OpenAIDashboardScraper|CodexStatusProbe|ClaudeStatusProbe|Sparkle" Sources Package.swift Scripts
```

## Preflight Gate

Preflight artifact:

- `docs/lite/preflight.md`

It captures only:

- endpoint URL
- HTTP status
- key/field presence
- pass/fail

No secrets, emails, raw bodies, or numeric account values should be committed there.

Mandatory rerun triggers after any rebase/change touching:

- `Package.swift`
- `Sources/CodexBarCore/UsageFetcher.swift`
- any provider descriptor
- any file under `Sources/CodexBarCore/Providers/Codex/`
- any file under `Sources/CodexBarCore/Providers/Claude/`

## Config Contract (Lite)

Retained fields:

- `version`
- `providers[]`
- provider `id`, `enabled`, `source`

Allowed provider IDs:

- `codex`
- `claude`

Allowed source values:

- `auto`
- `oauth`

Lite semantics:

- `auto` and `oauth` are treated identically

Dropped/ignored legacy fields:

- `apiKey`
- `cookieHeader`
- `cookieSource`
- `region`
- `workspaceID`
- `tokenAccounts`

## Repository Layout

- `Sources/CodexBarCore/Providers/Claude/ClaudeLiteFetcher.swift`
- `Sources/CodexBarCore/Providers/Codex/CodexLiteFetcher.swift`
- `Sources/CodexBarCore/Providers/LitePolicy.swift`
- `Scripts/setup-lite.sh`
- `docs/lite/preflight.md`

## Attribution and Licensing

This project is based on upstream CodexBar and preserves its MIT license obligations.

- upstream source: [steipete/CodexBar](https://github.com/steipete/CodexBar)
- reference implementation for lightweight fetch model: [shipshitdev/meterbar.app](https://github.com/shipshitdev/meterbar.app)

See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE) for details.

## Maintenance (Rebase Workflow)

```bash
git fetch origin
git rebase origin/main
```

After any rebase that touches preflight trigger paths:

1. rerun preflight checks
2. run `swift build` + `swift test`
3. rerun setup script
4. verify helper CLI usage outputs
