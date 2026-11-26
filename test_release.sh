#!/bin/bash
# Exercise the release script against a private local Git remote.
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_ALLOW_PROTOCOL=file
git init -q --bare "$tmp/origin"
git init -q -b main "$tmp/work"
cd "$tmp/work"
git config user.name "Release Test"
git config user.email "release@example.invalid"
git remote add origin "$tmp/origin"
cp "$src/kcm" "$src/release.sh" .
git add kcm release.sh
git commit -qm initial
git push -q origin main
initial=$(git rev-parse HEAD)

echo pending > unrelated
git add unrelated
if ./release.sh 99.0.0 > "$tmp/log" 2>&1; then
  echo "Release accepted unrelated staged work" >&2
  exit 1
fi
test "$(git rev-parse HEAD)" = "$initial"
git diff --quiet -- kcm
test "$(git diff --cached --name-only)" = unrelated

git restore --staged unrelated
echo '# local edit' >> kcm
if ./release.sh 99.0.0 > "$tmp/log" 2>&1; then
  echo "Release accepted local edits to kcm" >&2
  exit 1
fi
test "$(git rev-parse HEAD)" = "$initial"
test "$(tail -n 1 kcm)" = '# local edit'
git restore kcm

# Reject the first push after the commit and tag are created.
printf '#!/bin/sh\nexit 1\n' > "$tmp/origin/hooks/pre-receive"
chmod +x "$tmp/origin/hooks/pre-receive"
if ./release.sh 99.0.0 > "$tmp/log" 2>&1; then
  echo "A rejected push must fail the release" >&2
  exit 1
fi
tag=$(git rev-parse refs/tags/v99.0.0)
rm "$tmp/origin/hooks/pre-receive"
./release.sh 99.0.0 > "$tmp/log" 2>&1
test "$(git --git-dir="$tmp/origin" rev-parse --verify refs/tags/v99.0.0)" = "$tag"
test "$(git --git-dir="$tmp/origin" rev-parse main)" = "$(git rev-parse HEAD)"
