# Release Process

## Local Release (Developer)

```bash
./release.sh 0.5.0
```

**What happens:**
1. Updates version in `kcm` script (lines 3 & 9)
2. Commits `kcm` with message "Release v0.5.0"
3. Creates annotated tag `v0.5.0`
4. Pushes commit + tag to `origin main`

**Result:** Tag push triggers GitHub Actions workflow

## CI Release (Automated)

Triggered by tag push (`v*`)

**Test job:**
- Runs `test_kcm.sh` on macOS

**Release job** (after tests pass):
1. Creates the GitHub release, attaching the `kcm` script as the release asset
2. Computes the SHA256 of the `kcm` asset
3. Clones [`tyom/homebrew-tap`](https://github.com/tyom/homebrew-tap) (using the
   `HOMEBREW_TAP_TOKEN` secret) and updates `Formula/kcm.rb` with the new
   `url`, `version`, and `sha256`
4. Commits and pushes the formula bump to the tap

## Dry Run

```bash
./release.sh --dry-run 0.5.0
```

Shows what would happen without making changes.

## Notes

- The Homebrew formula lives in [`tyom/homebrew-tap`](https://github.com/tyom/homebrew-tap),
  not in this repo. It is bumped automatically by the Release workflow — never hand-edit it.
- Requires a `HOMEBREW_TAP_TOKEN` repository secret: a token with write access to
  `tyom/homebrew-tap`.
