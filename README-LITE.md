# CodexBar Lite

CodexBar Lite keeps CodexBar UI surfaces (menu bar, cards, widget, merge icon mode, cost display) while enforcing a lightweight acquisition policy.

## Lite invariants

- Providers: `codex` and `claude` only.
- Allowed acquisition: local credentials + direct `URLSession` API call.
- Forbidden acquisition: WebView scraping, browser cookie decryption/import, PTY/CLI probes, RPC app-server probes.
- Codex credentials: `~/.codex/auth.json`.
- Claude credentials: Keychain service `Claude Code-credentials`, then `~/.claude` fallback.
- `401/403` behavior: terminal auth error with explicit login guidance (`codex login` / `claude login`).
- No retry loops, no fallback cascades, no background token refresh writes in lite mode.

## Preflight gate

Preflight output is tracked in:
- `docs/lite/preflight.md`

Mandatory preflight rerun triggers:
- Any rebase.
- Any change touching:
  - `Package.swift`
  - `Sources/CodexBarCore/UsageFetcher.swift`
  - Any provider descriptor file
  - Any file under `Sources/CodexBarCore/Providers/Codex/`
  - Any file under `Sources/CodexBarCore/Providers/Claude/`

## Build/install

Use the setup script:

```bash
./Scripts/setup-lite.sh
```

The script enforces:
- branch check
- credential checks
- mandatory MeterBar removal guard
- package build + install to `/Applications/CodexBar.app`

## Notes

- `source` config values `auto` and `oauth` are retained for compatibility but are treated identically in lite mode.
- `CodexBarCLI` remains bundled in `CodexBar.app/Contents/Helpers/CodexBarCLI`.
