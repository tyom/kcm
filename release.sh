#!/bin/bash
# Bump the script version and publish its commit and annotated tag together.
set -euo pipefail

dry_run=false
version=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        *) if [ -n "$version" ]; then echo "Expected one version" >&2; exit 1; fi
           version="$arg" ;;
    esac
done
if ! [[ "$version" =~ ^[[:alnum:]][[:alnum:].+_-]*$ ]] || ! git check-ref-format "refs/tags/v$version"; then
    echo "Usage: $0 [--dry-run] <version>, for example 0.5.0" >&2
    exit 1
fi
if [ "$(git branch --show-current)" != main ]; then
    echo "Run releases from main" >&2
    exit 1
fi
if ! git diff --cached --quiet || ! git diff --quiet -- kcm; then
    echo "The Git index and kcm must be clean before a release." >&2
    exit 1
fi

tag="v$version"
tag_exists=false
if git show-ref --verify --quiet "refs/tags/$tag"; then
    tag_exists=true
    if [ "$(git rev-parse "refs/tags/$tag^{commit}")" != "$(git rev-parse HEAD)" ] ||
        [ "$(./kcm version)" != "kcm version $version" ]; then
        echo "$tag already exists for a different commit or version." >&2
        exit 1
    fi
fi

if [ "$dry_run" = true ]; then
    echo "Would release $tag from main and push main and its tag to origin."
    exit 0
fi

if [ "$(./kcm version)" != "kcm version $version" ]; then
    if sed --version >/dev/null 2>&1; then inplace=(-i); else inplace=(-i ''); fi
    sed "${inplace[@]}" -e "s/^_KCM_VERSION=.*/_KCM_VERSION=\"$version\"/" \
        -e "s/^# Version: .*/# Version: $version/" kcm
    git commit -m "Release $tag" -- kcm
fi
if [ "$tag_exists" = false ]; then
    git tag -a "$tag" -m "Release $tag"
fi
git push --atomic --no-follow-tags origin refs/heads/main "refs/tags/$tag"
echo "Published $tag. The Release workflow updates the GitHub release and Homebrew tap."
