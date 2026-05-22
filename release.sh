#!/bin/bash
# Script to create a new release: bump the version in `kcm`, commit, tag, and push.
# Pushing the tag triggers the Release workflow, which creates the GitHub release
# (with the `kcm` asset) and bumps Formula/kcm.rb in tyom/homebrew-tap.

set -euo pipefail

# Parse arguments
DRY_RUN=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Usage: $0 [--dry-run] <version>"
    echo "Example: $0 0.5.0"
    echo "Example: $0 --dry-run 0.5.0"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN MODE - No changes will be committed or pushed"
    echo ""
fi

echo "Creating release v${VERSION}..."
echo ""

# Detect sed type for portability (BSD vs GNU)
if sed --version >/dev/null 2>&1; then
    # GNU sed
    SED_INPLACE=(sed -i)
else
    # BSD sed (macOS)
    SED_INPLACE=(sed -i '')
fi

# Update version in kcm script
echo "Updating version in kcm script..."
if [ "$DRY_RUN" = true ]; then
    echo "  Would update VERSION and header comment to ${VERSION}"
else
    "${SED_INPLACE[@]}" "s/^VERSION=\".*\"/VERSION=\"${VERSION}\"/" kcm
    "${SED_INPLACE[@]}" "s/^# Version: .*/# Version: ${VERSION}/" kcm
fi

# Commit changes
echo "Committing changes..."
if [ "$DRY_RUN" = true ]; then
    echo "  Would commit: kcm"
    echo "  Message: Release v${VERSION}"
else
    git add kcm
    # Check if there are actual changes to commit
    if git diff --cached --quiet; then
        echo "  No changes to commit - files already at version ${VERSION}"
        echo "  Skipping tag creation and push"
        exit 0
    fi
    git commit -m "Release v${VERSION}"
fi

# Create and push tag
echo "Creating and pushing tag..."
if [ "$DRY_RUN" = true ]; then
    echo "  Would create tag: v${VERSION}"
    echo "  Would push: origin main --tags"
else
    git tag -a "v${VERSION}" -m "Release v${VERSION}"
    git push origin main --tags
fi

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN COMPLETE - No actual changes were made"
    echo ""
    echo "To perform the actual release, run:"
    echo "  $0 ${VERSION}"
else
    echo "Release v${VERSION} created successfully!"
    echo ""
    echo "The Release workflow will publish the GitHub release and bump the"
    echo "Homebrew formula in tyom/homebrew-tap. Users can then install/upgrade with:"
    echo "  brew install tyom/tap/kcm"
    echo "  brew upgrade kcm"
fi
