# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Developers on a small team who share a repo and work on macOS. Each person keeps their own credentials on their own Mac. They already use `.env` files for local development and want the secrets out of plain text without changing how the project runs.

kcm must stay optional for teammates. Someone who doesn't install it, or doesn't use a Mac, keeps real values in a gitignored `.env.local` and the shared scripts still work.

A solo developer can use kcm the same way, but the team case is the primary one.

## Product Purpose

kcm is a command-line tool for macOS. It stores secrets in the Keychain, leaves `keychain://` references in `.env` files, and fills them in when a command runs through `kcm use`.

Success means it is a useful personal tool, shared in case it helps others. Being clear and accurate matters more than adoption. Nothing about the project should push a visitor harder than the facts do.

## Positioning

kcm works with the `.env` files a project already has. `kcm import` moves the plain values into the Keychain and writes the references into the same files. `kcm use` then merges those same files, and a variable already set in the shell wins, as with dotenv. A team does not have to adopt a new file format, a service or an account.

## Operating Context

- Local development on the developer's own Mac. kcm reads the Keychain of the logged-in user.
- Projects with `.env`, `.env.local`, `.env.<mode>` and `.env.<mode>.local` files, including monorepos where a closer folder overrides the root.
- Shared repos where committed scripts call a small `sh` wrapper, so the same script runs with or without kcm.
- Installed with Homebrew (`brew install tyom/tap/kcm`) or by downloading the script.
- macOS shows a password or Touch ID prompt the first time kcm reads a secret.

## Capabilities and Constraints

- Commands: `add`, `remove`, `show`, `copy`, `ls`, `use`, `import`, `export`, `install-wrapper`.
- One bash script. It needs macOS and Bash 3.2 or later and has no other dependencies.
- Not for CI runners, production credentials, shared Macs or highly sensitive data. Any process running as the user can read the Keychain entries kcm creates. `SECURITY.md` states these limits and they must not be softened.
- `keychain://` references belong in gitignored files. Committed env files should not contain them.
- Terms to keep consistent: "reference" for a `keychain://NAME` value, "hint" for the comment given with `add -c`, "wrapper" for the script from `install-wrapper`.
- Undecided: none recorded.

## Brand Commitments

- Name: kcm, short for Keychain Master.
- Voice: dry and quiet. Plain, factual copy with no jokes in headings or body text. Small touches a developer notices on a second look are welcome.
- British spelling in prose and interface labels. US spelling in code, identifiers and commit messages.
- Palette chosen by the owner for the landing page: Evergreen `#16302b`, Vintage Grape `#694873`, Desert Sand `#f3d3bd`, Muted Teal `#85b79d`, Mahogany Red `#bd1e1e`.

## Evidence on Hand

- `README.md`: full command reference, parsing rules and worked examples, including the sample import picker output.
- `SECURITY.md`: known limits, when kcm is and isn't appropriate, and how it compares with other tools.
- `ARCHITECTURE.md`: technical design.
- `docs/index.html`: the landing page, deployed to GitHub Pages by `.github/workflows/pages.yml`.
- `test_kcm.sh` and `test_release.sh`: the test suites, run in CI on macOS.

There are no testimonials, user counts, benchmarks, press or logo. Future work must not invent them.

## Product Principles

1. Keep the `.env` workflow. A team should be able to adopt kcm without changing file names, load order or how the app starts.
2. Never make kcm a requirement for a teammate. Anything shared has to work without it.
3. Say what it does not protect. State the limits wherever the benefits are stated.
4. Accuracy before persuasion. Show real commands and real output, and claim nothing the README can't back.
5. Stay small. One script and the tools macOS ships, with no service, account or dependency.
