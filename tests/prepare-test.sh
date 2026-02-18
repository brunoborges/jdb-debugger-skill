#!/usr/bin/env bash
# prepare-test.sh — Prepare an isolated test directory for interactive debugging.
#
# Sets up a temporary folder with compiled classes, plugin files, and scripts,
# then writes the test prompt to prompt.txt. The user can cd into the directory
# and launch Claude or Copilot interactively.
#
# Usage:
#   ./tests/prepare-test.sh [--no-plugin]
#
# Options:
#   --no-plugin   Only copy compiled classes and prompt.txt (skip plugin files)
#
# Prerequisites:
#   - JDK with javac on PATH
set -euo pipefail

NO_PLUGIN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-plugin) NO_PLUGIN=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--no-plugin]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[prep]${NC} $*"; }
pass() { echo -e "${GREEN}[OK]${NC}   $*"; }
fail() { echo -e "${RED}[ERR]${NC}  $*"; }

# ─────────────────────────────────────────────
# Verify prerequisites
# ─────────────────────────────────────────────
if ! command -v javac &>/dev/null; then
  fail "javac not found. Install a JDK."
  exit 1
fi

SAMPLE_SRC="$REPO_ROOT/sample-app/WarningAppTest.java"
CONSOLE_SRC="$REPO_ROOT/sample-app/ConsoleAppTest.java"
if [[ ! -f "$SAMPLE_SRC" ]]; then
  fail "Sample source not found: $SAMPLE_SRC"
  exit 1
fi
if [[ ! -f "$CONSOLE_SRC" ]]; then
  fail "Sample source not found: $CONSOLE_SRC"
  exit 1
fi

# ─────────────────────────────────────────────
# Create work directory
# ─────────────────────────────────────────────
_tmpbase="${TMPDIR:-/tmp}"
WORKDIR=$(mktemp -d "${_tmpbase%/}/jdb-test-XXXXXX")

log "Creating test directory: $WORKDIR"

# Compile sample app
log "Compiling sample app with debug symbols..."
mkdir -p "$WORKDIR/classes"
javac -g -d "$WORKDIR/classes" "$SAMPLE_SRC" "$CONSOLE_SRC"

if [[ "$NO_PLUGIN" == false ]]; then
  # Plugin descriptor
  mkdir -p "$WORKDIR/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/plugin.json" "$WORKDIR/.claude-plugin/"

  # Agents
  cp -r "$REPO_ROOT/agents" "$WORKDIR/agents"

  # Skill scripts
  mkdir -p "$WORKDIR/skills/jdb-debugger/scripts"
  cp "$REPO_ROOT/skills/jdb-debugger/scripts/"*.sh "$WORKDIR/skills/jdb-debugger/scripts/"
  chmod +x "$WORKDIR/skills/jdb-debugger/scripts/"*.sh

  # Skill documentation
  cp "$REPO_ROOT/skills/jdb-debugger/SKILL.md" "$WORKDIR/skills/jdb-debugger/"

  # References (if they exist)
  if [[ -d "$REPO_ROOT/skills/jdb-debugger/references" ]]; then
    cp -r "$REPO_ROOT/skills/jdb-debugger/references" "$WORKDIR/skills/jdb-debugger/"
  fi

  # Permissions (for Claude)
  mkdir -p "$WORKDIR/.claude"
  cat > "$WORKDIR/.claude/settings.local.json" <<'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(javac:*)",
      "Bash(java:*)",
      "Bash(jdb:*)",
      "Bash(JDB_BP_DELAY=*)",
      "Bash(bash:*)",
      "Bash(cat:*)",
      "Bash(ls:*)",
      "Bash(find:*)",
      "Edit",
      "Read",
      "Write"
    ]
  }
}
SETTINGS
fi

# ─────────────────────────────────────────────
# Copy prompt.txt
# ─────────────────────────────────────────────
cp "$SCRIPT_DIR/prompt.txt" "$WORKDIR/prompt.txt"

# ─────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────
pass "Test directory ready: $WORKDIR"
echo ""
echo -e "${BOLD}To start an interactive session:${NC}"
echo ""
echo "  cd $WORKDIR"
echo ""
echo -e "  ${BOLD}Claude:${NC}  claude --plugin-dir ."
echo -e "  ${BOLD}Copilot:${NC} copilot"
echo ""
echo -e "Then paste or reference the prompt from ${BOLD}prompt.txt${NC}."
echo ""
echo -e "${CYAN}Tip:${NC} To clean up afterwards, run: rm -rf $WORKDIR"
