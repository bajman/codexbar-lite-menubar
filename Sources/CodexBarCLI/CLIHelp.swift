import CodexBarCore
import Foundation

extension CodexBarCLI {
    static func usageHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar usage [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)]
                       [--no-credits] [--no-color] [--pretty] [--status] [--source <auto|oauth>]
                       [--antigravity-plan-debug] [--augment-debug]

        Description:
          Print usage from enabled providers as text (default) or JSON. Honors your in-app toggles.
          Output format: use --json (or --format json) for JSON on stdout; use --json-output for JSON logs on stderr.
          Lite mode uses direct OAuth/API fetch for Codex.
          Claude --source auto uses the same lightweight quota probe as Claude Code and falls back to local logs
          only when live auth is unavailable.

        Global flags:
          -h, --help      Show help
          -V, --version   Show version
          -v, --verbose   Enable verbose logging
          --no-color      Disable ANSI colors in text output
          --log-level <trace|verbose|debug|info|warning|error|critical>
          --json-output   Emit machine-readable logs (JSONL) to stderr

        Examples:
          codexbar usage
          codexbar usage --provider claude
          codexbar usage --format json --provider all --pretty
          codexbar usage --provider all --json
          codexbar usage --status
          codexbar usage --provider codex --source oauth --format json --pretty
        """
    }

    static func costHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar cost [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)]
                       [--no-color] [--pretty] [--refresh]

        Description:
          Print local token cost usage from Claude/Codex JSONL logs. This does not require web or CLI access.
          Uses cached scan results unless --refresh is provided.

        Examples:
          codexbar cost
          codexbar cost --provider claude --format json --pretty
        """
    }

    static func configHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar config validate [--format text|json]
                                 [--json]
                                 [--json-only]
                                 [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                                 [-v|--verbose]
                                 [--pretty]
          codexbar config dump [--format text|json]
                             [--json]
                             [--json-only]
                             [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                             [-v|--verbose]
                             [--pretty]

        Description:
          Validate or print the CodexBar config file (default: validate).

        Examples:
          codexbar config validate --format json --pretty
          codexbar config dump --pretty
        """
    }

    static func rootHelp(version: String) -> String {
        """
        CodexBar \(version)

        Usage:
          codexbar [--format text|json]
                  [--json]
                  [--json-only]
                  [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                  [--provider \(ProviderHelp.list)]
                  [--no-credits] [--no-color] [--pretty] [--status] [--source <auto|oauth>]
                  [--antigravity-plan-debug] [--augment-debug]
          codexbar cost [--format text|json]
                       [--json]
                       [--json-only]
                       [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>] [-v|--verbose]
                       [--provider \(ProviderHelp.list)] [--no-color] [--pretty] [--refresh]
          codexbar config <validate|dump> [--format text|json]
                                        [--json]
                                        [--json-only]
                                        [--json-output] [--log-level <trace|verbose|debug|info|warning|error|critical>]
                                        [-v|--verbose]
                                        [--pretty]

        Global flags:
          -h, --help      Show help
          -V, --version   Show version
          -v, --verbose   Enable verbose logging
          --no-color      Disable ANSI colors in text output
          --log-level <trace|verbose|debug|info|warning|error|critical>
          --json-output   Emit machine-readable logs (JSONL) to stderr

        Examples:
          codexbar
          codexbar --format json --provider all --pretty
          codexbar --provider all --json
          codexbar cost --provider claude --format json --pretty
          codexbar config validate --format json --pretty
        """
    }
}
