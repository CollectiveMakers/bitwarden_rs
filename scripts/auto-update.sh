#!/usr/bin/env bash
set -euo pipefail

# Automatic Vaultwarden update & deploy for cron
# Checks for new releases, updates master, merges into clever, pushes to trigger deploy.
# Handles the known Dockerfile merge conflict (linux/amd64 platform override).
#
# Usage:
#   ./scripts/auto-update.sh           # run update
#   ./scripts/auto-update.sh --check   # only check, exit 0 if up-to-date, 2 if update available

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_DIR/logs"
LOG_FILE="$LOG_DIR/auto-update-$(date +%Y%m%d-%H%M%S).log"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
    log "ERROR: $*"
    exit 1
}

# Resolve the Dockerfile platform conflict automatically.
# We keep upstream content but force linux/amd64 instead of $BUILDPLATFORM / $TARGETPLATFORM.
resolve_dockerfile_conflict() {
    local file="$1"
    if grep -q "<<<<<<" "$file" 2>/dev/null; then
        log "Resolving merge conflict in $file..."
        # Accept upstream (theirs) then patch platform variables to linux/amd64
        git checkout --theirs "$file"
        sed -i '' \
            -e 's/FROM --platform=\$BUILDPLATFORM/FROM --platform=linux\/amd64/g' \
            -e 's/FROM --platform=\$TARGETPLATFORM/FROM --platform=linux\/amd64/g' \
            "$file"
        git add "$file"
        log "Conflict resolved in $file"
        return 0
    fi
    return 1
}

cd "$REPO_DIR"

# Ensure we don't run with dirty state
if ! git diff --quiet 2>/dev/null; then
    die "Working tree is dirty. Aborting."
fi

log "Fetching upstream releases..."
git fetch vaultwarden --tags --quiet

LATEST_TAG=$(git tag --sort=-v:refname | head -1)
CURRENT_TAG=$(git describe --tags --abbrev=0 master 2>/dev/null || echo "unknown")

log "Current: $CURRENT_TAG | Latest: $LATEST_TAG"

if [[ "$CURRENT_TAG" == "$LATEST_TAG" ]]; then
    log "Already up to date."
    exit 0
fi

if $CHECK_ONLY; then
    log "Update available: $CURRENT_TAG -> $LATEST_TAG"
    exit 2
fi

ORIGINAL_BRANCH=$(git branch --show-current)

cleanup() {
    if [[ "$(git branch --show-current)" != "$ORIGINAL_BRANCH" ]]; then
        git checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Step 1: Update master
log "Updating master: $CURRENT_TAG -> $LATEST_TAG..."
git checkout master --quiet
git merge "$LATEST_TAG" --no-edit --quiet || die "Failed to merge $LATEST_TAG into master"
git push origin master --quiet || die "Failed to push master"
log "master updated and pushed."

# Step 2: Merge into clever
log "Merging master into clever..."
git checkout clever --quiet

if git merge master --no-edit --quiet 2>/dev/null; then
    log "Merge succeeded cleanly."
else
    log "Merge conflict detected, attempting auto-resolution..."
    CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
    RESOLVED=true

    while IFS= read -r file; do
        case "$file" in
            docker/Dockerfile.debian|docker/Dockerfile.alpine|docker/Dockerfile.j2)
                resolve_dockerfile_conflict "$file" || { RESOLVED=false; break; }
                ;;
            *)
                log "Unknown conflict in $file — cannot auto-resolve."
                RESOLVED=false
                break
                ;;
        esac
    done <<< "$CONFLICT_FILES"

    if ! $RESOLVED; then
        git merge --abort
        die "Could not auto-resolve all conflicts. Manual intervention needed."
    fi

    git commit --no-edit --quiet || die "Failed to commit merge"
    log "Merge conflicts resolved automatically."
fi

# Step 3: Deploy
log "Pushing clever to origin (triggers Clever Cloud deploy)..."
git push origin clever --quiet || die "Failed to push clever"

log "Vaultwarden updated $CURRENT_TAG -> $LATEST_TAG and deploy triggered."

# Cleanup old logs (keep last 30)
ls -t "$LOG_DIR"/auto-update-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
