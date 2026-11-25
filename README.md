# KCM - Keychain Master

[![Tests](https://github.com/tyom/kcm/actions/workflows/test.yml/badge.svg)](https://github.com/tyom/kcm/actions/workflows/test.yml)

A secure command-line utility for managing secrets in macOS Keychain with seamless `.env` file integration.

## Features

- **Secure Storage**: Store sensitive data in macOS Keychain instead of plain text files
- **Environment Integration**: Seamlessly resolve `keychain://` placeholders in `.env` files
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

Multiline secrets such as PEM keys work through stdin. Adding a name that already exists updates its value.

After adding, you'll get a `.env` entry like:

```
DATABASE_URL="keychain://DATABASE_URL"
```

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

### Inspecting what `use` loads

Run `kcm use` without a command to list the variables it would load, with the file each one comes from. Values stay hidden:

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

# List all accessible secrets
kcm ls

# List secrets matching a pattern
kcm ls "DATABASE*"
kcm ls "*_KEY"

# Note: Only shows secrets that kcm can access
# Some app-specific secrets may have access restrictions

# Remove a secret
kcm remove OLD_API_KEY
```

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

When you run `kcm use -- <command>`, all `keychain://` references are resolved from the Keychain. If a secret is missing, kcm prints a warning and passes the `keychain://` text through unchanged.

Parsing rules:

- Values are passed to the command as plain text. kcm never runs them through a shell, so `$`, `&` or `;` in a value stay as they are.
- Single or double quotes around a value are removed. A quoted value can span several lines.
- Text after the closing quote is ignored, so `API_KEY="keychain://API_KEY" # staging` works. In an unquoted value, a `#` is part of the value.
- An `export ` prefix is allowed: `export PORT=3000`.
- Lines starting with `#`, blank lines and lines without a valid variable name are skipped.
- Windows (CRLF) line endings are fine.

## Security

Secrets stay in the macOS Keychain, which encrypts them. `kcm add` passes the value to `security` on stdin, so it doesn't show up in `ps` (values over about 2 KB are the exception). `.env` values are never run as code.

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

### CI/CD Integration

```bash
# Store deployment credentials
kcm add AWS_ACCESS_KEY_ID
kcm add AWS_SECRET_ACCESS_KEY

# Deploy script
kcm use --env-file .env.deploy -- ./deploy.sh
```

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

# Or remove directly via security command
security delete-generic-password -s "KEY_NAME"
```

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
