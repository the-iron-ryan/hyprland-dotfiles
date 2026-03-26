#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# upstream-sync.sh — Smart upstream merge for forked dotfiles
#
# Merges upstream/main into your fork while protecting your custom files.
# Protected files are listed in protected.txt (one pattern per line).
#
# Usage:
#   ./dev/upstream-sync.sh              # interactive merge
#   ./dev/upstream-sync.sh --dry-run    # preview only, no changes
#   ./dev/upstream-sync.sh --auto       # non-interactive (abort on conflict)
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTECTED_FILE="$SCRIPT_DIR/protected.txt"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
LOCAL_BRANCH="main"

DRY_RUN=0
AUTO_MODE=0

# ── Parse args ────────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        --auto)       AUTO_MODE=1 ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--auto]"
            echo "  --dry-run   Preview changes without modifying anything"
            echo "  --auto      Non-interactive mode (abort on conflict)"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}::${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
ok()    { echo -e "${GREEN}✓${NC}  $*"; }
err()   { echo -e "${RED}✗${NC}  $*"; }

# ── Preflight checks ─────────────────────────────────────────────────────────

cd "$REPO_DIR"

# Ensure we're on the right branch
current_branch=$(git branch --show-current)
if [[ "$current_branch" != "$LOCAL_BRANCH" ]]; then
    err "Not on $LOCAL_BRANCH (currently on $current_branch). Aborting."
    exit 1
fi

# Ensure working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
    err "Working tree has uncommitted changes. Commit or stash first."
    git status --short
    exit 1
fi

# Ensure upstream remote exists
if ! git remote | grep -q "^${UPSTREAM_REMOTE}$"; then
    err "Remote '$UPSTREAM_REMOTE' not found. Add it with:"
    echo "  git remote add upstream https://github.com/mylinuxforwork/dotfiles.git"
    exit 1
fi

# ── Load protected patterns ──────────────────────────────────────────────────

PROTECTED_PATTERNS=()
if [[ -f "$PROTECTED_FILE" ]]; then
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue
        PROTECTED_PATTERNS+=("$line")
    done < "$PROTECTED_FILE"
    info "Protected patterns (${#PROTECTED_PATTERNS[@]}): ${PROTECTED_PATTERNS[*]}"
else
    warn "No protected.txt found at $PROTECTED_FILE"
fi

# ── Fetch upstream ────────────────────────────────────────────────────────────

info "Fetching $UPSTREAM_REMOTE/$UPSTREAM_BRANCH..."
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"

# ── Check divergence ─────────────────────────────────────────────────────────

LOCAL_HEAD=$(git rev-parse HEAD)
UPSTREAM_HEAD=$(git rev-parse "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")
MERGE_BASE=$(git merge-base HEAD "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")

if [[ "$LOCAL_HEAD" == "$UPSTREAM_HEAD" ]]; then
    ok "Already up to date with $UPSTREAM_REMOTE/$UPSTREAM_BRANCH."
    exit 0
fi

commits_behind=$(git rev-list --count HEAD.."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH")
commits_ahead=$(git rev-list --count "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH"..HEAD)

info "Status: ${BOLD}$commits_ahead${NC} commits ahead, ${BOLD}$commits_behind${NC} commits behind upstream"

# ── Preview upstream changes ──────────────────────────────────────────────────

info "Files changed upstream since last sync:"
changed_files=$(git diff --stat "$MERGE_BASE".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" -- | tail -1)
echo "  $changed_files"
echo

# Show which upstream changes touch protected files
protected_conflicts=()
for pattern in "${PROTECTED_PATTERNS[@]}"; do
    matches=$(git diff --name-only "$MERGE_BASE".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" -- | grep -i "$pattern" || true)
    if [[ -n "$matches" ]]; then
        protected_conflicts+=("$pattern")
        warn "Upstream changed protected file(s) matching '$pattern':"
        echo "$matches" | sed 's/^/    /'
    fi
done

# Show new commits
echo
info "Upstream commits to merge ($commits_behind):"
git log --oneline --no-merges "$MERGE_BASE".."$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" | head -20
if (( commits_behind > 20 )); then
    echo "  ... and $((commits_behind - 20)) more"
fi
echo

# ── Dry run exits here ───────────────────────────────────────────────────────

if (( DRY_RUN )); then
    info "Dry run complete. No changes made."
    exit 0
fi

# ── Confirm ───────────────────────────────────────────────────────────────────

if (( ! AUTO_MODE )); then
    echo -e "${BOLD}Merge strategy:${NC}"
    echo "  1. Merge upstream/main into local main"
    echo "  2. Auto-resolve conflicts on protected files (keep OURS)"
    echo "  3. Pause on other conflicts for manual resolution"
    echo
    read -rp "Proceed with merge? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        info "Aborted."
        exit 0
    fi
fi

# ── Backup current state ─────────────────────────────────────────────────────

BACKUP_TAG="pre-sync-$(date +%Y%m%d-%H%M%S)"
git tag "$BACKUP_TAG" HEAD
ok "Created backup tag: $BACKUP_TAG (restore with: git reset --hard $BACKUP_TAG)"

# ── Merge ─────────────────────────────────────────────────────────────────────

info "Merging $UPSTREAM_REMOTE/$UPSTREAM_BRANCH..."

# Attempt the merge — don't auto-commit so we can fix protected files
if git merge --no-commit --no-ff "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" 2>/dev/null; then
    ok "Merge applied cleanly."
else
    warn "Merge has conflicts. Resolving protected files..."
fi

# ── Auto-resolve protected file conflicts (keep ours) ─────────────────────────

resolved_count=0
manual_conflicts=()

# Get list of conflicted files
conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null || true)

if [[ -n "$conflicted" ]]; then
    while IFS= read -r file; do
        is_protected=0
        for pattern in "${PROTECTED_PATTERNS[@]}"; do
            if echo "$file" | grep -qi "$pattern"; then
                is_protected=1
                break
            fi
        done

        if (( is_protected )); then
            # Keep our version of protected files
            git checkout --ours -- "$file"
            git add "$file"
            ok "Protected file conflict auto-resolved (kept ours): $file"
            ((resolved_count++))
        else
            manual_conflicts+=("$file")
        fi
    done <<< "$conflicted"
fi

# Also restore protected files that merged cleanly but we want to keep our version
for pattern in "${PROTECTED_PATTERNS[@]}"; do
    matching_files=$(git diff --name-only HEAD -- | grep -i "$pattern" 2>/dev/null || true)
    if [[ -n "$matching_files" ]]; then
        while IFS= read -r file; do
            # Only restore if not already handled as a conflict
            if [[ ! " ${manual_conflicts[*]:-} " =~ " $file " ]]; then
                git checkout HEAD -- "$file" 2>/dev/null && \
                    ok "Protected file restored (kept ours): $file" || true
            fi
        done <<< "$matching_files"
    fi
done

# ── Handle remaining conflicts ────────────────────────────────────────────────

if (( ${#manual_conflicts[@]} > 0 )); then
    echo
    err "Unresolved conflicts in ${#manual_conflicts[@]} file(s):"
    for f in "${manual_conflicts[@]}"; do
        echo "    $f"
    done
    echo

    if (( AUTO_MODE )); then
        err "Auto mode: aborting merge due to unresolved conflicts."
        git merge --abort
        git tag -d "$BACKUP_TAG" 2>/dev/null || true
        exit 1
    fi

    echo -e "${YELLOW}Resolve these manually, then:${NC}"
    echo "  git add <resolved-files>"
    echo "  git commit"
    echo
    echo "Or abort with:"
    echo "  git merge --abort"
    echo "  git tag -d $BACKUP_TAG"
    exit 2
fi

# ── Commit the merge ──────────────────────────────────────────────────────────

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
git commit -m "sync: upstream merge $TIMESTAMP

Merged $commits_behind commits from $UPSTREAM_REMOTE/$UPSTREAM_BRANCH.
Protected files preserved: ${PROTECTED_PATTERNS[*]}
Backup tag: $BACKUP_TAG"

ok "Merge committed successfully!"
echo
info "Summary:"
echo "  Commits merged:      $commits_behind"
echo "  Protected resolved:  $resolved_count"
echo "  Manual conflicts:    0"
echo "  Backup tag:          $BACKUP_TAG"
echo
info "Next steps:"
echo "  1. Test your config:  hyprctl reload"
echo "  2. Push if happy:     git push origin $LOCAL_BRANCH"
echo "  3. Rollback if not:   git reset --hard $BACKUP_TAG"
