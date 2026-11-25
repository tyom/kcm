# KCM Architecture

Technical overview of KCM's design and implementation decisions.

## Design Philosophy

### Security by Default

Input validation, no `eval` or `source`. Values are only exported, so they are never run as code.

### Developer Experience

Simple commands, works with existing `.env` workflows, clear error messages.

### Single-File Distribution

One bash script, no external dependencies, easy to audit.

### macOS-First

Leverages native Keychain via the `security` command.

## Core Architecture

### Command Flow

```
User Input → Validation → Keychain Operation → Output
```

All commands follow this pattern with appropriate validation at each step.

### Secret Storage

Secrets are stored as generic password entries in the macOS login keychain using `security add-generic-password`. The service name is the environment variable name (e.g., `API_KEY`).

Each entry kcm writes also gets kind `kcm secret`, creator code `kcm ` and a comment: `Added by kcm`, or `Imported by kcm from <file>` for `import`. Keychain stores these attributes unencrypted, so they hold no secret data.

### Environment Resolution

The `use` command:

1. Parses `.env` files line-by-line (never using `eval`)
2. Merges the files, then resolves `keychain://` references in the winning values by querying the keychain, except for variables the caller already exported
3. Exports variables not already in the environment and executes the user command via `exec`

## Security Architecture

### Validation

1. **Key Names**: Must match `^[A-Za-z][A-Za-z0-9_]*$`
2. **Variable Names**: Must be valid shell identifiers

Values are not filtered. kcm never evaluates them, so a `$` or `;` in a value is just a character.

### Safe Parsing

Environment files are parsed manually without shell interpretation:

- Split on first `=` only
- Accept an optional `export ` prefix and CRLF line endings
- Text after a closing quote is ignored, so `KEY="value" # note` works
- Store in arrays before exporting
- No code evaluation

## Key Design Decisions

### Why Bash?

Universal on macOS, direct access to system commands, simple distribution. The single-file constraint outweighs language limitations.

### Why Generic Keychain Items?

The CLI `security` command doesn't support app-specific ACLs. This trades fine-grained access control for simplicity and CLI compatibility.

### Why Not Custom Encryption?

macOS Keychain provides OS-managed encryption, system authentication, and battle-tested security. Following "don't roll your own crypto."

### Why 45 Seconds for Clipboard?

Balances usability (enough time to paste) with security (minimal exposure). Empirically sufficient for normal workflows.

### Why `exec` for Command Execution?

Replaces the script process with the target command, ensuring:

- Correct signal propagation
- No lingering process in memory
- Clean process tree

## Implementation Patterns

### Keychain Operations

`store_secret` writes a value as hex through `security -i` on stdin, then reads it back, because `security -i` exits 0 even when a command fails. `read_secret` parses `security find-generic-password -g`, since `-w` prints hex for values with newlines.

### Import

`import` parses env files directly (the parser never resolves references), so `keychain://` values stay as text, and uses the line range the parser records for each assignment. It stores every picked value with `store_secret` (which reads it back) before touching any file, then rewrites each file once through a temp file in the same folder and `mv`. A failed store leaves its line as it was. A file whose checksum changed since the scan is skipped, since its line ranges no longer hold. It is checked after the prompts and again just before `mv`. This narrows the window but is not atomic: an edit between the last check and `mv` is overwritten. A failed store or rewrite, or a file or Keychain entry that changed after the scan, makes `import` exit 1. Values you chose to skip do not. A value the Keychain already holds is only referenced, so that entry keeps its old attributes. There is no backup file, because it would keep the plain values on disk.

### Environment Processing

Uses parallel arrays (`PROCESSED_ENV_NAMES`, `PROCESSED_ENV_VALUES`) to parse everything before exporting anything.

### Pattern Matching

Converts shell wildcards to regex and uses a two-phase filter:

1. Pattern match during keychain parsing
2. Accessibility check for each candidate

### Error Handling

Strict mode (`set -euo pipefail`) with explicit error handling for user-facing operations. Errors include helpful messages and exit codes.

## Trade-offs

### Simplicity vs. Features

- **No folders/tags**: Use naming conventions (e.g., `PROD_API_KEY`)
- **No rotation tracking**: External workflow
- **No multi-user**: Per-user keychain model
- Keeps the tool focused and maintainable

### Access Control vs. CLI Compatibility

- **Generic keychain items**: Any process can access
- **Better than alternatives**: Still encrypted, better than plain text
- **Clear documentation**: Users understand the security model
- Appropriate for development secrets, not production credentials

## Performance Characteristics

### Bottlenecks

- Keychain operations: ~50-100ms per `security` command
- File I/O: Negligible for typical `.env` files
- Process spawning: Minimized through native bash features

### Optimizations

- Batch operations where possible
- Single keychain dump for listing
- Native pattern matching over external commands
- No lingering parent process after `exec`

## Testing Strategy

Tests are organized into functional groups (basic commands, validation, security, edge cases) with isolated execution. Each test uses unique identifiers and cleanup ensures no artifacts remain.

Helper assertions (`assert_equals`, `assert_contains`, `assert_exit_code`) provide clear failure messages.

## Future Considerations

### Potential Enhancements

- Secret expiration/rotation metadata
- Integration with other secret backends (abstraction layer)
- Optional audit logging
- Native macOS app for better ACL support

### Explicit Non-Goals

- Cross-platform support (macOS-specific by design)
- Complex organization (naming conventions suffice)
- Secret generation (dedicated tools exist)
- Multi-user secrets (per-user model)

## File Structure

```
kcm                  # Main executable (single file)
test_kcm.sh          # Test suite
SECURITY.md          # User-facing security policy
ARCHITECTURE.md      # This document
README.md            # User documentation
```

All functionality is in the single `kcm` script for easy distribution and auditing.

---

For security policy and vulnerability reporting, see [SECURITY.md](SECURITY.md).
