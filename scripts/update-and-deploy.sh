#!/usr/bin/env bash
set -euo pipefail

# Update Vaultwarden to the latest release and deploy to Clever Cloud
# Usage: ./scripts/update-and-deploy.sh [--dry-run]

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ==="
fi

# Fetch upstream tags
echo "Fetching upstream releases..."
git fetch vaultwarden --tags

# Find the latest release tag (semver sorted)
LATEST_TAG=$(git tag --sort=-v:refname | head -1)
CURRENT_TAG=$(git describe --tags --abbrev=0 master 2>/dev/null || echo "unknown")

echo "Current version on master: $CURRENT_TAG"
echo "Latest upstream release:   $LATEST_TAG"

if [[ "$CURRENT_TAG" == "$LATEST_TAG" ]]; then
    echo "Already up to date."
    exit 0
fi

echo ""
echo "Changelog ($CURRENT_TAG → $LATEST_TAG):"
TOTAL=$(git log --oneline "$CURRENT_TAG..$LATEST_TAG" | wc -l | tr -d ' ')
git log --oneline "$CURRENT_TAG..$LATEST_TAG" | head -30 || true
if [[ "$TOTAL" -gt 30 ]]; then
    echo "... and $((TOTAL - 30)) more commits"
fi

if $DRY_RUN; then
    echo ""
    echo "[dry-run] Would update master to $LATEST_TAG and merge into clever."
    exit 0
fi

echo ""
read -rp "Update to $LATEST_TAG and deploy? [y/N] " confirm
if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 1
fi

# Update master to latest tag
echo ""
echo "Updating master to $LATEST_TAG..."
git checkout master
git merge "$LATEST_TAG" --no-edit
git push origin master

# Merge into clever and deploy
echo ""
echo "Merging master into clever..."
git checkout clever
git merge master --no-edit

echo ""
echo "Pushing clever to origin (triggers Clever Cloud deploy)..."
git push origin clever

echo ""
echo "Done! Vaultwarden updated to $LATEST_TAG and deployment triggered."
