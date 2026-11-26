# KCM - Keychain Master

[![Tests](https://github.com/tyom/kcm/actions/workflows/test.yml/badge.svg)](https://github.com/tyom/kcm/actions/workflows/test.yml)

A secure command-line utility for managing secrets in macOS Keychain with seamless `.env` file integration.

## Features

- **Secure Storage**: Store sensitive data in macOS Keychain instead of plain text files
- **Environment Integration**: Seamlessly resolve `keychain://` placeholders in `.env` files
- **Env File Discovery**: Find and merge `.env` files from the current folder up to the git root. Variables already in your environment win
- **Import**: Move plain values from `.env` files into Keychain and replace them with `keychain://` references
- **Export**: Resolve env files into plain values in a file or on the clipboard, for example to share them
- **Inspection**: Run `kcm use` without a command to see which variables would load and where each comes from
- **Clipboard Management**: Copy secrets to clipboard with automatic clearing after 45 seconds
- **Pattern Matching**: List and search secrets using wildcards
- **Simple CLI**: Intuitive commands for adding, removing, and managing secrets
- **Zero Dependencies**: Pure bash script using native macOS security tools

## Installation

### Using Homebrew

```bash
brew install tyom/tap/kcm
```

> Previously installed from the `tyom/kcm` tap? Switch over with:
>
> ```bash
> brew untap tyom/kcm && brew install tyom/tap/kcm
> ```

### Manual Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/tyom/kcm/main/kcm

# Make it executable
chmod +x kcm

# Move to your PATH
sudo mv kcm /usr/local/bin/
```

## Usage

### Adding Secrets

Add a secret to the Keychain and get the `.env` entry:

```bash
# Interactive mode (prompts for value)
kcm add DATABASE_URL

# From stdin
echo "secret-value" | kcm add TOKEN -
cat ~/secret-file.txt | kcm add AWS_SECRET -
```

Add a hint with `-c` to remember what a secret is for or where it came from:

```bash
kcm add STRIPE_KEY -c "Test mode key, from the Stripe dashboard"
```

`kcm ls` shows the hint next to the name, and Keychain Access shows it as the comment. Adding the name again without `-c` updates the value and keeps the hint. A hint can be up to 200 characters, and can't use the wording of kcm's own comments (`Added by kcm`, `Imported by kcm ...`). It is not encrypted, so don't put anything secret in it.

To add a hint to a secret you already have, pipe its value back in:

```bash
kcm show STRIPE_KEY | kcm add STRIPE_KEY - -c "Test mode key, from the Stripe dashboard"
```

Multiline secrets such as PEM keys work through stdin. Adding a name that already exists updates its value. If the name matches several Keychain entries ambiguously, `add` refuses to change any of them.

After adding, you'll get a `.env` entry like:

```
DATABASE_URL="keychain://DATABASE_URL"
```

### Importing existing .env values

Move plain values you already have in env files into the Keychain:

```bash
kcm import                  # scan env files from here up to the git root
kcm import -e .env.local    # or a single file
```

kcm lists every plain value with a masked preview and ticks the ones that look like secrets: names with KEY, SECRET, TOKEN, PASSWORD and similar, known token prefixes (`sk-`, `ghp_`, `AKIA`…), URLs with a password, private keys and long random strings. NOTES says what matched. After the `·` it says what changed the default, such as a public prefix, a file tracked by git or an existing Keychain entry.

```
       NAME                    FILE          VALUE      NOTES
> [x]  OPENAI_API_KEY          ./.env.local  sk-p…9f2c  name has KEY, starts with sk-
  [x]  STRIPE_KEY              ./.env.local  sk_l…a1b2  name has KEY, starts with sk_live_ · in Keychain, same value
  [x]  GITHUB_TOKEN            ./.env.local  ghp_…0123  name has TOKEN, starts with ghp_ · in Keychain, different value
  [ ]  EXPO_PUBLIC_SENTRY_DSN  ./.env.local  http…6848  name has DSN, looks random · public, so unticked
  [ ]  PORT                    ./.env        ****
  ✓    DATABASE_URL            ./.env.local             keychain://DATABASE_URL
  !    REDIS_URL               ./.env.local             keychain://REDIS_URL missing from Keychain
↑/↓ move  space toggle  a all  enter continue  q quit
```

Names already in the Keychain stand out. Green means the Keychain has the same value, so kcm only writes the reference. Yellow means it has a different value, and kcm asks what to do after you press Enter. Lines that already hold a `keychain://` reference are listed at the end and can't be picked: dimmed with ✓ when the entry exists, yellow with ! when it's missing.

Use ↑/↓ (or `j`/`k`) to move, Space to tick or untick, `a` to tick all (or untick all when everything is ticked) and Enter to continue. Long lists scroll. When input isn't a terminal, for example piped from a script, kcm prints a numbered list instead and reads numbers or ranges such as `3` or `1-2`.

- Each value is stored under its variable name, without leading underscores (`_TOKEN` is stored as `TOKEN`). If that name is already in the Keychain with a different value, kcm asks whether to overwrite it, keep the Keychain value, store under another name (default `<REPO>_<NAME>`) or skip.
- Files tracked by git and names with a public prefix (`NEXT_PUBLIC_`, `VITE_` and similar) are never ticked for you. If you import from a tracked file, rotate the secret: the old value stays in git history.
- After a final confirmation, kcm stores each value, reads it back, and only then replaces its line with `NAME="keychain://LABEL"`. A comment after the value goes with it. Other lines stay as they are. kcm keeps no backup, since it would hold the plain values.
- Without `-e`, every `.env` and `.env.*` file is scanned, not only the current `NODE_ENV`. Files ending in `.example`, `.sample` or `.template` are skipped.
- Quitting at any prompt changes nothing.

### Exporting resolved values

Turn your env files back into plain values, for example to give them to someone without kcm:

```bash
kcm export -c                 # copy to clipboard, cleared after 45 seconds
kcm export -o shared.env      # write a new file
kcm export                    # view it in less
kcm export -e .env.local | …  # or pipe it
```

`export` loads the same files as `kcm use`, and variables already in your environment win in the same way. It writes one `NAME='value'` line per variable, in quotes that kcm and dotenv both read as is, so `kcm use -e shared.env` gives the same values back. Values that contain `'` use double quotes instead.

- If a `keychain://` entry is missing, export fails and writes nothing.
- `-o` creates the file readable only by you and never overwrites one. It refuses a folder other users can write to, unless it has the sticky bit and you or root own it, like `/tmp`. It doesn't check parent folders or ACLs, so export into your own folders (see [SECURITY.md](SECURITY.md)). If git doesn't ignore the file, kcm warns.
- Without `-o` or `-c`, the output opens in `less` in a terminal, like `kcm use --full`, so secrets don't stay in your scrollback. When piped, kcm prints it as is.

The file holds your secrets in plain text. Pasting from the clipboard into a password manager or a secure note is safer than sending a file around.

### Using Secrets in Applications

Run any command with secrets from your `.env` file automatically resolved:

```bash
# Find and merge .env files automatically
kcm use -- npm run dev

# Load .env.production instead of .env.development
NODE_ENV=production kcm use -- node server.js

# Specify a custom env file
kcm use --env-file .env.production -- node server.js

# Access resolved variables in scripts
kcm use -- bash -c 'echo $DATABASE_URL'
```

Without `--env-file`, `kcm use` searches from the current folder up to the git root (the folder with `.git`). In each folder it looks for:

| File | Priority |
| --- | --- |
| `.env.<mode>.local` | highest |
| `.env.local` | |
| `.env.<mode>` | |
| `.env` | lowest |

`<mode>` is `$NODE_ENV`, or `development` if unset. kcm merges every file it finds, and a closer folder wins over a parent folder, so in a monorepo `apps/web/.env.local` overrides the root `.env`. Outside a git repo, kcm only checks the current folder. It prints the files it loaded to stderr:

```
ℹ Loaded ./.env.local, ../../.env
```

`--env-file` loads exactly one file and skips the search.

Variables already set in your environment win over env files, as with dotenv. kcm doesn't look them up in the Keychain, so `DATABASE_URL=postgres://localhost/test kcm use -- npm test` uses that URL without a Keychain prompt. This also means a script run through `kcm use` can call `kcm use` again without loading secrets twice.

### Optional kcm in shared scripts

To call kcm from committed scripts without making it a requirement, add a small wrapper to the repo:

```bash
kcm install-wrapper            # asks for the location, default scripts/with-env
kcm install-wrapper bin/env    # or give it directly
```

The location is relative to the git root. kcm won't overwrite an existing file. The wrapper is a plain `sh` script, so it works without kcm:

```sh
#!/bin/sh
# Resolve keychain:// secrets with kcm when it is installed, otherwise run the command as is.
# See https://github.com/tyom/kcm
command -v kcm >/dev/null 2>&1 && exec kcm use -- "$@"
exec "$@"
```

Commit it and use it in scripts, for example in `package.json`:

```json
"scripts": {
  "dev": "scripts/with-env vite"
}
```

For this to work for everyone:

- Keep `keychain://` references out of committed env files. Each person puts them in `.env.local` (gitignored). People without kcm put real values there instead.
- Without kcm, the wrapper loads no env files. That's fine for tools that read `.env` themselves, such as Vite, Next.js, Node with dotenv or Docker Compose. A plain shell script that needs the values must load them in its fallback, for example with `set -a; . ./.env.local; set +a`. That runs the file as shell code, so it has to be valid shell.

### Inspecting what `use` loads

Run `kcm use` without a command to list variable names and their source files without reading passwords from Keychain.

```
$ kcm use
ℹ Loaded ./.env.local, ../../.env
API_KEY       ./.env.local
DATABASE_URL  ../../.env
```

Add `--show-values` (`-s`) to check the resolved values without exposing them. Values of 24 characters or more show the first and last 4 (`API_KEY=sk-a…9f2c`), and shorter ones show `****`.

`--full` shows complete values. In a terminal they open in `less`, which clears the screen when you quit, so secrets don't stay in your scrollback. When piped (`kcm use --full | grep DB`), it prints plain `NAME=value` lines. To get a single value, use `kcm show NAME` or `kcm copy NAME`.

### Managing Secrets

```bash
# Show a secret value
kcm show DATABASE_URL

# Copy to clipboard (cleared after 45 seconds, unless you copied something else since)
kcm copy API_KEY

# List kcm's secrets
kcm ls

# List secrets matching a pattern
kcm ls "DATABASE*"
kcm ls "*_KEY"

# Other apps' entries are hidden. Untagged entries that look like
# an older kcm added them are listed in a separate group

# Remove a secret
kcm remove OLD_API_KEY
```

When several Keychain entries share a service name, kcm prefers its tagged entry, then a legacy entry for your user account. An untagged entry under another account is used only when no other entry has that name. If the best match is ambiguous, give the entries distinct service names in Keychain Access before retrying.

## Environment File Format

Your `.env` files can use the special `keychain://` prefix to reference Keychain secrets:

```env
# .env example
DATABASE_URL="keychain://DATABASE_URL"
API_KEY="keychain://API_KEY"
REDIS_URL="keychain://REDIS_URL"

# Regular values work too
PORT=3000
NODE_ENV=development
```

When you run `kcm use -- <command>`, all `keychain://` references are resolved from the Keychain. If a secret is missing or unreadable, kcm prints a warning and passes the `keychain://` text through unchanged. If a name matches several Keychain entries ambiguously, kcm stops without running the command.

Parsing rules:

- Values are passed to the command as plain text. kcm never runs them through a shell, so `$`, `&` or `;` in a value stay as they are.
- Single or double quotes around a value are removed. A quoted value can span several lines. A closing quote on a line of its own keeps the line break before it, as in dotenv.
- Escapes are not expanded: `"a\nb"` stays a backslash and an `n`, where dotenv would make a line break. Put real line breaks in a multiline value such as a PEM key.
- Text after the closing quote is ignored, so `API_KEY="keychain://API_KEY" # staging` works. In an unquoted value, a `#` is part of the value.
- An unfinished quoted value stops parsing. The error names the file and opening line.
- `kcm use` rejects assignments to Bash-managed variables such as `UID`, `RANDOM` and `IFS` before reading secrets. Variables already exported by the caller still take precedence.
- An `export ` prefix is allowed: `export PORT=3000`.
- Lines starting with `#`, blank lines and lines without a valid variable name are skipped.
- Windows (CRLF) line endings are fine.

## Security

Secrets stay in the macOS Keychain, which encrypts them. `kcm add` passes the value to `security` on stdin, so it doesn't show up in `ps` (values over about 2 KB are the exception). `.env` values are never run as code.

In Keychain Access, kcm's entries show the kind "kcm secret". The comment says where a value came from: "Added by kcm", "Imported by kcm from ~/Code/app/.env.local", or the hint you gave with `add -c`. These details are not encrypted, unlike the value. Entries from older versions of kcm get them the next time you add that name, or import a different value under it. An import that finds the same value only writes the reference and leaves the entry as it is.

**See [SECURITY.md](SECURITY.md) for full security policy, best practices, and limitations.**

## Examples

### Setting Up a New Project

```bash
# Add your database credentials
kcm add DATABASE_URL

# Add your API keys
kcm add STRIPE_KEY
kcm add SENDGRID_KEY

# Create your .env file
cat > .env << EOF
DATABASE_URL="keychain://DATABASE_URL"
STRIPE_KEY="keychain://STRIPE_KEY"
SENDGRID_KEY="keychain://SENDGRID_KEY"
PORT=3000
EOF

# Run your application
kcm use -- npm run dev
```

### A Separate Env File for One Script

```bash
# Store credentials for a staging deploy from your Mac
kcm add STAGING_AWS_ACCESS_KEY_ID
kcm add STAGING_AWS_SECRET_ACCESS_KEY

# Point the names the script reads at those entries
cat > .env.staging << EOF
AWS_ACCESS_KEY_ID="keychain://STAGING_AWS_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="keychain://STAGING_AWS_SECRET_ACCESS_KEY"
EOF

# Run the script with only that file
kcm use --env-file .env.staging -- ./deploy.sh
```

kcm reads the Keychain of the logged-in user, so it is for your own machine, not for CI runners or production credentials (see [SECURITY.md](SECURITY.md)).

### Team Collaboration

Share `.env` files with `keychain://` placeholders in your repository. Each team member stores their own credentials locally:

```bash
# Team member setup
git clone https://github.com/yourteam/project
cd project

# Each member adds their own credentials
kcm add DATABASE_URL  # Enter their dev database URL
kcm add API_KEY        # Enter their personal API key

# Everyone can now run the app with their own credentials
kcm use -- npm start
```

To let teammates skip kcm and keep plain values in their `.env.local`, see [Optional kcm in shared scripts](#optional-kcm-in-shared-scripts).

## Requirements

- macOS (uses native `security` command)
- Bash 3.2 or higher (the version macOS ships)
- Access to macOS Keychain

## Important Notes

### macOS Security Prompts

When using kcm for the first time or accessing certain secrets, **macOS will display a security dialog** asking for your password or Touch ID. This is normal behavior - macOS is protecting your Keychain and requires your authorization to allow kcm to access stored secrets.

You may see prompts like:

- "kcm wants to use your confidential information stored in [KEY_NAME] in your keychain"
- You can click "Always Allow" to avoid repeated prompts for the same secret

## Troubleshooting

### Permission Issues

If you encounter permission errors, ensure you have access to the login keychain:

```bash
security list-keychains
```

### Viewing Keychain Entries

You can verify entries directly using macOS security command:

```bash
security find-generic-password -s "YOUR_KEY_NAME" -w
```

### Clearing Stuck Secrets

If a secret seems stuck or corrupted:

```bash
# Remove using kcm
kcm remove KEY_NAME

# Or remove directly via security command. Give the account, because
# without -a it deletes the first entry with that name, whoever owns it.
security delete-generic-password -s "KEY_NAME" -a "$USER"
```

If `kcm remove` says the name is ambiguous, open Keychain Access, find the entries with that name, and delete or rename the one you no longer need.

## Development

**See [RELEASE.md](RELEASE.md) for release process.**

**See [ARCHITECTURE.md](ARCHITECTURE.md) for technical design and implementation details.**

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created by Tyom Semonov

## Acknowledgments

Built with ♥︎ using native macOS security tools for maximum compatibility and security.
