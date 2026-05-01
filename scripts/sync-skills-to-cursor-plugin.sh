#!/usr/bin/env bash
#
# sync-skills-to-cursor-plugin.sh
#
# Copy superpowers content from this repo into the installed Cursor Superpowers
# plugin cache (skills, commands, agents, hooks, .cursor-plugin, assets, and
# CLAUDE.md / AGENTS.md) so the Agent matches your local checkout. The plugin
# hash under ~/.cursor/plugins may change when the extension updates; this
# script discovers current plugin roots automatically.
#
# Cursor-only by design: Cursor (on this machine) also loads skills from
# ~/.claude/plugins/cache/**. To avoid duplicate/divergent copies of the same
# skill, ~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>
# is expected to be a symlink pointing at the Cursor hashed dir this script
# writes to. That way a single rsync here updates both IDEs.
#
#   ~/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7
#     -> ~/.cursor/plugins/cache/cursor-public/superpowers/<hash>
#
# If that symlink is missing, run (once):
#   mv  ~/.claude/plugins/cache/claude-plugins-official/superpowers/<ver> \
#       ~/.claude/plugins/cache/claude-plugins-official/superpowers/<ver>.bak
#   ln -s ~/.cursor/plugins/cache/cursor-public/superpowers/<hash> \
#       ~/.claude/plugins/cache/claude-plugins-official/superpowers/<ver>
#
# Content synced (all must exist in the repo except assets/):
#   skills/  commands/  agents/  hooks/  .cursor-plugin/  [assets/]
#   CLAUDE.md  AGENTS.md  (if present)
#
# Usage:
#   ./scripts/sync-skills-to-cursor-plugin.sh
#   ./scripts/sync-skills-to-cursor-plugin.sh -n                 # dry-run
#   ./scripts/sync-skills-to-cursor-plugin.sh -y                 # no confirm
#   ./scripts/sync-skills-to-cursor-plugin.sh --skill brainstorm # only skills/<name>/
#   SUPERPOWERS_ROOT=/path/to/superpowers ./scripts/...
#
# Requires: bash, rsync. Optional: CURSOR_PLUGINS_ROOT (default ~/.cursor/plugins)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="${SUPERPOWERS_ROOT:-$REPO_ROOT}"
CURSOR_ROOT="${CURSOR_PLUGINS_ROOT:-"$HOME/.cursor/plugins"}"
DRY_RUN=0
YES=0
SINGLE_SKILL=""

# Directories that ship with the Cursor plugin (see .cursor-plugin/plugin.json)
REQUIRED_SUBDIRS=(skills commands agents hooks .cursor-plugin)
OPTIONAL_SUBDIRS=(assets)

ROOT_FILES=(CLAUDE.md AGENTS.md)

usage() {
  sed -n '/^# Usage:/,/^# Requires/p' "$0" | sed '/^# Requires/d' | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -y|--yes)     YES=1; shift ;;
    --skill)      SINGLE_SKILL="${2:-}"; shift 2 ;;
    -h|--help)    usage 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage 2
      ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

command -v rsync >/dev/null || die "rsync not found in PATH"
[[ -d "$REPO_ROOT" ]]      || die "not a directory: $REPO_ROOT (set SUPERPOWERS_ROOT?)"

for d in "${REQUIRED_SUBDIRS[@]}"; do
  [[ -d "$REPO_ROOT/$d" ]] || die "missing required path $REPO_ROOT/$d (incomplete superpowers checkout?)"
done

if [[ -n "$SINGLE_SKILL" ]]; then
  [[ -d "$REPO_ROOT/skills/$SINGLE_SKILL" ]] || die "no skills/$SINGLE_SKILL under $REPO_ROOT"
fi

# Plugin root: parent of each .../superpowers/<hash>/skills (marketplace cache install)
# OR .../superpowers/skills (local install under ~/.cursor/plugins/local/superpowers/).
# Both layouts ship the same content; only the install location differs.
mapfile -t DEST_SKILLS < <(find "$CURSOR_ROOT" -type d \( -path "*/superpowers/*/skills" -o -path "*/superpowers/skills" \) 2>/dev/null | sort -u)
[[ ${#DEST_SKILLS[@]} -gt 0 ]] || die "no Cursor superpowers plugin under $CURSOR_ROOT — is superpowers installed? Try: find ~/.cursor/plugins -path '*superpowers*/skills' -type d"

rsync_a=(-a -v)
[[ $DRY_RUN -eq 1 ]] && rsync_a+=(--dry-run)

confirm() {
  [[ $YES -eq 1 ]] && return 0
  read -rp "$1 [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

echo "Source:  $REPO_ROOT"
if [[ -n "$SINGLE_SKILL" ]]; then
  echo "Scope:   only skills/${SINGLE_SKILL}/ (other plugin dirs unchanged)"
else
  scope="${REQUIRED_SUBDIRS[*]}"
  for d in "${OPTIONAL_SUBDIRS[@]}"; do
    [[ -d "$REPO_ROOT/$d" ]] && scope="$scope $d"
  done
  echo "Scope:   $scope + ${ROOT_FILES[*]} (if present)"
fi
echo "Destinations (plugin root = dirname of each .../skills):"
for s in "${DEST_SKILLS[@]}"; do
  echo "  $(dirname "$s")"
done
echo ""

[[ $DRY_RUN -eq 1 ]] || confirm "Overwrite the Cursor superpowers plugin with your repo copy?" || { echo "Aborted."; exit 1; }

for skills_dest in "${DEST_SKILLS[@]}"; do
  PLUGIN_ROOT="$(dirname "$skills_dest")"

  if [[ -n "$SINGLE_SKILL" ]]; then
    echo "rsync ${rsync_a[*]} → $skills_dest/$SINGLE_SKILL/"
    rsync "${rsync_a[@]}" "$REPO_ROOT/skills/$SINGLE_SKILL/" "$skills_dest/$SINGLE_SKILL/"
    continue
  fi

  for sub in "${REQUIRED_SUBDIRS[@]}"; do
    # skills/ is $skills_dest
    if [[ "$sub" == "skills" ]]; then
      echo "rsync ${rsync_a[*]} → $skills_dest/"
      rsync "${rsync_a[@]}" "$REPO_ROOT/skills/" "$skills_dest/"
    else
      echo "rsync ${rsync_a[*]} → $PLUGIN_ROOT/$sub/"
      rsync "${rsync_a[@]}" "$REPO_ROOT/$sub/" "$PLUGIN_ROOT/$sub/"
    fi
  done

  for sub in "${OPTIONAL_SUBDIRS[@]}"; do
    if [[ -d "$REPO_ROOT/$sub" ]]; then
      echo "rsync ${rsync_a[*]} → $PLUGIN_ROOT/$sub/"
      rsync "${rsync_a[@]}" "$REPO_ROOT/$sub/" "$PLUGIN_ROOT/$sub/"
    fi
  done

  for f in "${ROOT_FILES[@]}"; do
    if [[ -e "$REPO_ROOT/$f" ]]; then
      echo "rsync ${rsync_a[*]} → $PLUGIN_ROOT/$f"
      rsync "${rsync_a[@]}" "$REPO_ROOT/$f" "$PLUGIN_ROOT/"
    fi
  done
done

echo ""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run only; nothing was written."
else
  echo "Done. Start a new Agent chat (or restart Cursor) so the updated plugin content loads."
fi
