# CodexBar Lite Preflight

Generated: 2026-02-28T08:55:55.288364Z

## Scope
This artifact intentionally includes only endpoint URLs, HTTP statuses, field-name presence, and pass/fail outcomes.

Secret-safety checklist:
- [x] No tokens
- [x] No account identifiers or emails
- [x] No raw response bodies
- [x] No numeric usage values
- [x] Artifact reviewed for secrets before commit

## Toolchain
- `swift --version`: Apple Swift version 6.2.1 (swiftlang-6.2.1.4.6 clang-1700.4.4.1)
- `xcode-select --version`: xcode-select version 2416.
- `git --version`: git version 2.52.0
- `codex --version`: codex-cli 0.100.0
- `claude --version`: 2.1.63 (Claude Code)

## Endpoint Validation

### Codex
- Endpoint: `https://chatgpt.com/backend-api/wham/usage`
- HTTP status: `200`
- Top-level keys: `account_id, additional_rate_limits, code_review_rate_limit, credits, email, plan_type, promo, rate_limit, user_id`
- Required field presence:
  - `plan_type`: `True`
  - `rate_limit`: `True`
  - `rate_limit.primary_window`: `True`
  - `rate_limit.secondary_window`: `True`
- Pass: `True`

### Claude
- Endpoint: `https://api.anthropic.com/api/oauth/usage`
- Credential source used: `keychain`
- HTTP status: `200`
- Top-level keys: `extra_usage, five_hour, iguana_necktie, seven_day, seven_day_cowork, seven_day_oauth_apps, seven_day_opus, seven_day_sonnet`
- Required field presence:
  - `five_hour`: `True`
  - `seven_day`: `True`
- Pass: `True`

## Mandatory Preflight Rerun Triggers
Rerun this gate after any rebase or change touching:
- `Package.swift`
- `Sources/CodexBarCore/UsageFetcher.swift`
- Any provider descriptor file
- Any file under `Sources/CodexBarCore/Providers/Codex/`
- Any file under `Sources/CodexBarCore/Providers/Claude/`

## Overall Gate
- Codex: `True`
- Claude: `True`
- Overall pass: `True`
