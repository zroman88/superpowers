#!/usr/bin/env bash
#
# install-superpowers.sh — Install Superpowers plugin for Cursor and/or Claude Code
#
# Checks for ~/.cursor and ~/.claude directories and installs to whichever
# are present. Sets up hooks so skills auto-trigger on session start.
#
# Usage:
#   ./install-superpowers.sh                        # install from current repo checkout
#   ./install-superpowers.sh --source /path/to/repo # use a specific local checkout
#   ./install-superpowers.sh --uninstall            # remove installed files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR=""
UNINSTALL=false
INSTALLED_TARGETS=()

CURSOR_DIR="$HOME/.cursor"
CLAUDE_DIR="$HOME/.claude"
CURSOR_PLUGIN_DIR="$CURSOR_DIR/plugins/local/superpowers"
CLAUDE_PLUGIN_DIR="$CLAUDE_DIR/plugins/local/superpowers"

usage() {
  cat <<'EOF'
Usage: install-superpowers.sh [OPTIONS]

Options:
  --source PATH     Use a specific local checkout as the source
  --uninstall       Remove Superpowers from all detected targets
  -h, --help        Show this help

By default, installs from the repo containing this script.
EOF
  exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)    SOURCE_DIR="${2:-}"; shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h|--help)   usage 0 ;;
    *)           die "Unknown argument: $1. Run with --help for usage." ;;
  esac
done

# ── Uninstall ────────────────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
  info "Uninstalling Superpowers..."

  if [[ -d "$CURSOR_PLUGIN_DIR" ]]; then
    info "Removing $CURSOR_PLUGIN_DIR"
    rm -rf "$CURSOR_PLUGIN_DIR"
  fi

  if [[ -f "$CURSOR_DIR/hooks.json" ]]; then
    if grep -q "superpowers" "$CURSOR_DIR/hooks.json" 2>/dev/null; then
      info "Removing Cursor hooks.json (contained superpowers references)"
      rm -f "$CURSOR_DIR/hooks.json"
    fi
  fi

  if [[ -d "$CLAUDE_PLUGIN_DIR" ]]; then
    info "Removing $CLAUDE_PLUGIN_DIR"
    rm -rf "$CLAUDE_PLUGIN_DIR"
  fi

  info "Uninstall complete. Restart Cursor/Claude Code to take effect."
  exit 0
fi

# ── Resolve source directory ─────────────────────────────────────────────
if [[ -n "$SOURCE_DIR" ]]; then
  [[ -d "$SOURCE_DIR" ]] || die "Source directory does not exist: $SOURCE_DIR"
  [[ -f "$SOURCE_DIR/hooks/session-start" ]] || die "Not a valid superpowers repo: $SOURCE_DIR (missing hooks/session-start)"
else
  # Default: the repo this script lives in
  SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  [[ -f "$SOURCE_DIR/hooks/session-start" ]] || die "Cannot find superpowers repo at $SOURCE_DIR. Use --clone or --source."
fi

info "Source: $SOURCE_DIR"

# ── Validate source ──────────────────────────────────────────────────────
for required in skills hooks hooks/session-start .cursor-plugin/plugin.json; do
  [[ -e "$SOURCE_DIR/$required" ]] || die "Missing required path: $SOURCE_DIR/$required"
done

# ── Detect targets ───────────────────────────────────────────────────────
HAVE_CURSOR=false
HAVE_CLAUDE=false

if [[ -d "$CURSOR_DIR" ]]; then
  HAVE_CURSOR=true
  info "Detected Cursor at $CURSOR_DIR"
fi

if [[ -d "$CLAUDE_DIR" ]]; then
  HAVE_CLAUDE=true
  info "Detected Claude Code at $CLAUDE_DIR"
fi

if [[ "$HAVE_CURSOR" == false && "$HAVE_CLAUDE" == false ]]; then
  die "Neither ~/.cursor nor ~/.claude found. Install Cursor or Claude Code first."
fi

# ── Install function ─────────────────────────────────────────────────────
copy_plugin_files() {
  local dest="$1"
  info "Installing to $dest..."

  mkdir -p "$dest"

  local dirs_to_copy=(skills hooks commands agents assets .cursor-plugin .claude-plugin)
  for dir in "${dirs_to_copy[@]}"; do
    if [[ -d "$SOURCE_DIR/$dir" ]]; then
      rsync -a --delete "$SOURCE_DIR/$dir/" "$dest/$dir/"
    fi
  done

  local files_to_copy=(CLAUDE.md AGENTS.md README.md LICENSE package.json)
  for f in "${files_to_copy[@]}"; do
    if [[ -e "$SOURCE_DIR/$f" ]]; then
      cp -a "$SOURCE_DIR/$f" "$dest/"
    fi
  done

  chmod +x "$dest/hooks/session-start" 2>/dev/null || true
}

# ── Install for Cursor ───────────────────────────────────────────────────
if [[ "$HAVE_CURSOR" == true ]]; then
  info "Installing Superpowers for Cursor..."

  mkdir -p "$CURSOR_DIR/plugins/local"
  copy_plugin_files "$CURSOR_PLUGIN_DIR"

  # Set up hooks.json at ~/.cursor/hooks.json
  HOOKS_FILE="$CURSOR_DIR/hooks.json"
  HOOK_CMD="$CURSOR_PLUGIN_DIR/hooks/session-start"

  if [[ -f "$HOOKS_FILE" ]]; then
    if grep -q "superpowers" "$HOOKS_FILE" 2>/dev/null; then
      info "Cursor hooks.json already references superpowers — updating path"
    else
      warn "Cursor hooks.json exists but doesn't reference superpowers."
      warn "Backing up to $HOOKS_FILE.bak and overwriting."
      cp "$HOOKS_FILE" "$HOOKS_FILE.bak"
    fi
  fi

  cat > "$HOOKS_FILE" <<HOOKEOF
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "command": "$HOOK_CMD"
      }
    ]
  }
}
HOOKEOF

  INSTALLED_TARGETS+=("Cursor")
  info "Cursor installation complete."
  echo ""
  echo "  ┌──────────────────────────────────────────────────────────────┐"
  echo "  │  IMPORTANT: Disable third-party plugin imports in Cursor!   │"
  echo "  │                                                             │"
  echo "  │  1. Open Cursor Settings (gear icon)                        │"
  echo "  │  2. Go to 'Rules, Skills, Subagents'                        │"
  echo "  │  3. Turn OFF:                                               │"
  echo "  │     • Include third-party Plugins, Skills, and other        │"
  echo "  │       configs                                               │"
  echo "  │     • Automatically import agent configs from other tools   │"
  echo "  │                                                             │"
  echo "  │  This prevents Cursor from loading the marketplace version  │"
  echo "  │  of Superpowers, which would conflict with this local       │"
  echo "  │  installation.                                              │"
  echo "  └──────────────────────────────────────────────────────────────┘"
  echo ""
fi

# ── Install for Claude Code ──────────────────────────────────────────────
if [[ "$HAVE_CLAUDE" == true ]]; then
  info "Installing Superpowers for Claude Code..."

  mkdir -p "$CLAUDE_DIR/plugins/local"
  copy_plugin_files "$CLAUDE_PLUGIN_DIR"

  INSTALLED_TARGETS+=("Claude Code")
  info "Claude Code installation complete."
  echo ""
  echo "  Note: If you have the marketplace version of Superpowers installed"
  echo "  in Claude Code, disable it to avoid conflicts:"
  echo ""
  echo "    claude settings set enabledPlugins.superpowers@claude-plugins-official false"
  echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
info "Installation complete for: ${INSTALLED_TARGETS[*]}"
echo ""
echo "Next steps:"
echo "  1. Restart Cursor and/or Claude Code"
echo "  2. Open a new Agent chat and send: Let's make a python todo list"
echo "  3. If Superpowers is working, the brainstorming skill will auto-trigger"
echo "     before any code is written."
echo ""
echo "To update later, pull the repo and re-run this script:"
echo "  cd $SOURCE_DIR && git pull && ./scripts/install-superpowers.sh"
echo ""
echo "To uninstall:"
echo "  ./scripts/install-superpowers.sh --uninstall"
