#!/usr/bin/env bash
# Update an installed SCLAB Studio directory to the latest scripts WITHOUT git pull conflicts.
#
# install.sh edits tracked files in place (docker-compose.yml, common.env, settings.json, ...),
# so a plain "git pull" stops with conflicts. This script instead:
#   1. backs up every locally modified tracked file (inside .git/update-backup/<time>/),
#   2. fast-forwards the checkout to the latest upstream commit,
#   3. three-way merges each of your files: your installed values are kept, and the
#      upstream changes made since your checkout are applied on top.
# A file where both sides changed the same lines is NOT touched: your copy stays as it is and the
# upstream version is written next to it as <file>.upstream for a manual merge.
#
#   ./update-docker-images.sh               show incoming changes, ask, then update
#   ./update-docker-images.sh --check       only show what would happen (changes nothing)
#   ./update-docker-images.sh -y            do not ask for confirmation
#   ./update-docker-images.sh --ref <ref>   update to <ref> (default: upstream of the current branch)
#
# After updating, apply with ./update.sh (pull new images, rolling restart) or ./run.sh.
# Data (./data), certificates (./cert, ./jwt) and .init are untracked and never touched.
set -euo pipefail
cd "$(dirname "$0")"

CHECK_ONLY=0
ASSUME_YES=0
TARGET=""

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|-n) CHECK_ONLY=1 ;;
    -y|--yes)   ASSUME_YES=1 ;;
    --ref)
      shift
      [ "$#" -gt 0 ] || { echo "[Error] --ref needs a value." >&2; exit 1; }
      TARGET="$1"
      ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "[Error] Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

BACKUP_DIR=""
PREVIEW_DIR=""
MODIFIED_FILES=()
OLD_HEAD=""
UPDATED=0

# On an unexpected failure after files were reset, put the user's files back.
restore_backup() {
  local f
  [ "$UPDATED" -eq 0 ] && [ -n "$BACKUP_DIR" ] || return 0
  for f in ${MODIFIED_FILES[@]+"${MODIFIED_FILES[@]}"}; do
    if [ -f "$BACKUP_DIR/files/$f" ]; then
      mkdir -p "$(dirname "$f")"
      cat "$BACKUP_DIR/files/$f" > "$f"
    fi
  done
  echo "[Error] Update failed; your files were restored. Backup: $BACKUP_DIR" >&2
}

# 3-way merge. $1 local, $2 base, $3 upstream, $4 output. Prints nothing.
# Returns 0 = clean, 1 = conflicts (output holds markers).
three_way() {
  local rc=0
  cp "$1" "$4"
  git merge-file -q -L local -L base -L upstream "$4" "$2" "$3" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -gt 0 ] && return 1
  echo "[Error] git merge-file failed for $1" >&2
  return 2
}

main() {
  command -v git >/dev/null 2>&1 || { echo "[Error] git is required." >&2; exit 1; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "[Error] Not a git checkout." >&2; exit 1; }

  OLD_HEAD=$(git rev-parse HEAD)
  local branch
  branch=$(git symbolic-ref --short -q HEAD || true)

  echo "Fetching latest changes..."
  git fetch --quiet

  if [ -z "$TARGET" ]; then
    TARGET=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [ -z "$TARGET" ]; then
      echo "[Error] Branch '${branch:-detached HEAD}' has no upstream. Use: $0 --ref origin/<branch>" >&2
      exit 1
    fi
  fi
  local new_head
  new_head=$(git rev-parse --verify -q "$TARGET^{commit}") || { echo "[Error] Unknown ref: $TARGET" >&2; exit 1; }

  if [ "$new_head" = "$OLD_HEAD" ] || git merge-base --is-ancestor "$new_head" "$OLD_HEAD"; then
    echo "Already up to date ($(git rev-parse --short HEAD) on ${branch:-detached HEAD})."
    exit 0
  fi
  if ! git merge-base --is-ancestor "$OLD_HEAD" "$new_head"; then
    echo "[Error] Your checkout has commits that are not in $TARGET (diverged), so it cannot be fast-forwarded." >&2
    echo "        Resolve it manually, or reset the branch to $TARGET after saving your changes." >&2
    exit 1
  fi

  echo ""
  echo "Incoming changes ($branch -> $TARGET):"
  git log --oneline --no-decorate "$OLD_HEAD..$new_head" | sed 's/^/  /'

  # Tracked files you changed (install.sh, service-manage.sh, manual edits).
  while IFS= read -r f; do
    [ -n "$f" ] && MODIFIED_FILES+=("$f")
  done < <(git diff --name-only --relative --diff-filter=M HEAD)

  # Preview: which of your files also changed upstream, and would they merge cleanly?
  local f
  PREVIEW_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t sclab-update)
  trap 'rm -rf "$PREVIEW_DIR"; restore_backup' EXIT
  local n_keep=0 n_merge=0 n_conflict=0 n_gone=0
  local -a conflicts=()
  echo ""
  echo "Your locally modified files: ${#MODIFIED_FILES[@]}"
  for f in ${MODIFIED_FILES[@]+"${MODIFIED_FILES[@]}"}; do
    if ! git cat-file -e "$new_head:./$f" 2>/dev/null; then
      echo "  - $f: removed upstream (your copy will be kept)"
      n_gone=$((n_gone + 1))
    elif git diff --quiet "$OLD_HEAD" "$new_head" -- "$f"; then
      echo "  = $f: no upstream change (kept as is)"
      n_keep=$((n_keep + 1))
    else
      git show "$OLD_HEAD:./$f" > "$PREVIEW_DIR/base"
      git show "$new_head:./$f" > "$PREVIEW_DIR/theirs"
      if three_way "$f" "$PREVIEW_DIR/base" "$PREVIEW_DIR/theirs" "$PREVIEW_DIR/out"; then
        echo "  + $f: your values kept, upstream changes merged"
        n_merge=$((n_merge + 1))
      else
        echo "  ! $f: CONFLICT - your copy is kept, upstream saved as $f.upstream"
        n_conflict=$((n_conflict + 1))
        conflicts+=("$f")
      fi
    fi
  done

  if [ "$CHECK_ONLY" -eq 1 ]; then
    echo ""
    echo "--check: nothing was changed."
    exit 0
  fi

  if [ "$ASSUME_YES" -eq 0 ]; then
    local answer=""
    if [ -t 0 ]; then
      read -r -p "Update now? [Y/n]: " answer || answer=""
    fi
    case "${answer:-Y}" in
      [Yy]*) ;;
      *) echo "Cancelled."; exit 0 ;;
    esac
  fi

  # 1. Back up everything you changed (copies + a patch).
  BACKUP_DIR="$(git rev-parse --git-dir)/update-backup/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR/files"
  git diff --relative HEAD > "$BACKUP_DIR/local-changes.patch" || true
  for f in ${MODIFIED_FILES[@]+"${MODIFIED_FILES[@]}"}; do
    mkdir -p "$BACKUP_DIR/files/$(dirname "$f")"
    cp -p "$f" "$BACKUP_DIR/files/$f"
  done
  echo ""
  echo "Backup of your files: $BACKUP_DIR"

  # 2. Clean tree for those files, then fast-forward.
  if [ "${#MODIFIED_FILES[@]}" -gt 0 ]; then
    git checkout -q HEAD -- "${MODIFIED_FILES[@]}"
  fi
  # Untracked files that upstream now ships (e.g. a hand-copied update-docker-images.sh): identical ones
  # are removed so the fast-forward can create them, different ones are moved into the backup.
  while IFS= read -r f; do
    [ -n "$f" ] && [ -e "$f" ] || continue
    git ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue
    if git show "$new_head:./$f" 2>/dev/null | cmp -s - "$f"; then
      rm -f "$f"
    else
      mkdir -p "$BACKUP_DIR/untracked/$(dirname "$f")"
      mv "$f" "$BACKUP_DIR/untracked/$f"
      echo "Moved your untracked $f to $BACKUP_DIR/untracked/ (upstream now ships this file)."
    fi
  done < <(git diff --name-only --relative --diff-filter=A "$OLD_HEAD" "$new_head")
  if ! git merge --ff-only -q "$new_head"; then
    echo "[Error] Fast-forward failed (an untracked file may be in the way)." >&2
    exit 1
  fi

  # 3. Put your values back on top of the new files.
  for f in ${MODIFIED_FILES[@]+"${MODIFIED_FILES[@]}"}; do
    if [ ! -f "$f" ]; then
      mkdir -p "$(dirname "$f")"
      cat "$BACKUP_DIR/files/$f" > "$f"
    elif git diff --quiet "$OLD_HEAD" "$new_head" -- "$f"; then
      cat "$BACKUP_DIR/files/$f" > "$f"
    else
      git show "$OLD_HEAD:./$f" > "$PREVIEW_DIR/base"
      cp "$f" "$PREVIEW_DIR/theirs"
      if three_way "$BACKUP_DIR/files/$f" "$PREVIEW_DIR/base" "$PREVIEW_DIR/theirs" "$PREVIEW_DIR/out"; then
        cat "$PREVIEW_DIR/out" > "$f"
      else
        cp "$f" "$f.upstream"
        cat "$BACKUP_DIR/files/$f" > "$f"
      fi
    fi
  done
  UPDATED=1

  echo ""
  echo "Updated to $(git rev-parse --short HEAD)."
  echo "  merged with your values: $n_merge   unchanged upstream: $n_keep   removed upstream: $n_gone   conflicts: $n_conflict"
  if [ "$n_conflict" -gt 0 ]; then
    echo ""
    echo "Merge these by hand (your copy is in place, the new upstream file is <file>.upstream):"
    for f in "${conflicts[@]}"; do
      echo "  diff $f $f.upstream      # what upstream changed: git diff ${OLD_HEAD:0:7} ${new_head:0:7} -- $f"
    done
    echo "Delete the .upstream files when done."
  fi
  echo ""
  echo "Next: sudo ./update.sh   (pull new images and restart)   or   sudo ./run.sh"
}

main
exit 0
