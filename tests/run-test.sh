#!/usr/bin/env bash
# run-test.sh — Integration test for the jdb-agentic-debugger plugin.
#
# Validates that debugging agents can find bugs in a Java application
# WITHOUT access to source code — only compiled .class files and JDB scripts.
#
# Supports two agents: Claude Code CLI and GitHub Copilot CLI.
# By default, runs whichever CLIs are available. Use --agent to run one.
#
# Usage:
#   ./tests/run-test.sh [--agent claude|copilot|all] [--model <model>] [--max-budget <usd>] [--allow-all] [--verbose]
#
# Prerequisites:
#   - JDK with javac and jdb on PATH
#   - claude and/or copilot CLI installed and authenticated
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Timing & Report ---
TEST_START_EPOCH=$(date +%s)
TEST_START_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REPORT_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RESULTS_DIR="$SCRIPT_DIR/test-results"
mkdir -p "$RESULTS_DIR"
REPORT_FILE="/dev/null"
REPORT_FILES=()

# --- Defaults ---
AGENT_FILTER="all"
MODEL=""
MAX_BUDGET="5.00"
VERBOSE=false
ALLOW_ALL=false

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)    AGENT_FILTER="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    --max-budget) MAX_BUDGET="$2"; shift 2 ;;
    --verbose)  VERBOSE=true; shift ;;
    --allow-all) ALLOW_ALL=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--agent claude|copilot|all] [--model <model>] [--max-budget <usd>] [--allow-all] [--verbose]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# tee_report: append plain text (no ANSI codes) to the report file
tee_report() { sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT_FILE"; }

start_report() {
  local agent_name="$1"
  REPORT_FILE="$RESULTS_DIR/test-report-${agent_name}-${REPORT_TIMESTAMP}.txt"
  REPORT_FILES+=("$REPORT_FILE")
  {
    echo "========================================================"
    echo "  JDB Agentic Debugger — Test Report (${agent_name})"
    echo "========================================================"
    echo "Started at: $TEST_START_TS"
    echo ""
  } > "$REPORT_FILE"
}

finish_report() {
  local end_epoch end_ts elapsed min sec
  end_epoch=$(date +%s)
  end_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  elapsed=$((end_epoch - TEST_START_EPOCH))
  min=$((elapsed / 60))
  sec=$((elapsed % 60))
  {
    echo ""
    echo "========================================================"
    echo "  Timing"
    echo "========================================================"
    echo "Started at:  $TEST_START_TS"
    echo "Finished at: $end_ts"
    echo "Duration:    ${min}m ${sec}s (${elapsed}s total)"
    echo "========================================================"
  } >> "$REPORT_FILE"
  log "Test report saved to: $REPORT_FILE"
  REPORT_FILE="/dev/null"
}

log()  { echo -e "${CYAN}[test]${NC} $*" | tee >(tee_report); }
pass() { echo -e "${GREEN}[PASS]${NC} $*" | tee >(tee_report); }
fail() { echo -e "${RED}[FAIL]${NC} $*" | tee >(tee_report); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee >(tee_report); }

banner() {
  local agent_name="$1"
  local phase="$2"
  {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  ${agent_name} — ${phase}$(printf '%*s' $((38 - ${#agent_name} - ${#phase})) '')║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
  } | tee >(tee_report)
}

separator() {
  echo -e "${DIM}──────────────────────────────────────────────────${NC}" | tee >(tee_report)
}

# ─────────────────────────────────────────────
# Verify prerequisites
# ─────────────────────────────────────────────
log "Checking prerequisites..."

if ! command -v javac &>/dev/null; then
  fail "javac not found. Install a JDK."
  exit 1
fi

HAS_CLAUDE=false
HAS_COPILOT=false
command -v claude  &>/dev/null && HAS_CLAUDE=true
command -v copilot &>/dev/null && HAS_COPILOT=true

if [[ "$AGENT_FILTER" == "claude" && "$HAS_CLAUDE" == false ]]; then
  fail "claude CLI not found."; exit 1
fi
if [[ "$AGENT_FILTER" == "copilot" && "$HAS_COPILOT" == false ]]; then
  fail "copilot CLI not found."; exit 1
fi
if [[ "$AGENT_FILTER" == "all" && "$HAS_CLAUDE" == false && "$HAS_COPILOT" == false ]]; then
  fail "Neither claude nor copilot CLI found."; exit 1
fi

# Build list of agents to run
AGENTS=()
if [[ "$AGENT_FILTER" == "all" ]]; then
  [[ "$HAS_CLAUDE"  == true ]] && AGENTS+=("claude")
  [[ "$HAS_COPILOT" == true ]] && AGENTS+=("copilot")
else
  AGENTS+=("$AGENT_FILTER")
fi

log "Agents to test: ${AGENTS[*]}"

# ─────────────────────────────────────────────
# Compile .java → .class (with debug symbols)
# ─────────────────────────────────────────────
SAMPLE_SRC="$REPO_ROOT/tests/samples/WarningAppTest.java"
CONSOLE_SRC="$REPO_ROOT/tests/samples/ConsoleAppTest.java"
if [[ ! -f "$SAMPLE_SRC" ]]; then
  fail "Sample source not found: $SAMPLE_SRC"
  exit 1
fi
if [[ ! -f "$CONSOLE_SRC" ]]; then
  fail "Sample source not found: $CONSOLE_SRC"
  exit 1
fi

_tmpbase="${TMPDIR:-/tmp}"
BASE_WORKDIR=$(mktemp -d "${_tmpbase%/}/jdb-test-XXXXXX")
log "Base work directory: $BASE_WORKDIR"

cleanup() {
  if [[ "$VERBOSE" == true ]]; then
    warn "Keeping work directory for inspection: $BASE_WORKDIR"
  else
    rm -rf "$BASE_WORKDIR"
    log "Cleaned up $BASE_WORKDIR"
  fi
}
trap cleanup EXIT

log "Compiling sample app with debug symbols..."
mkdir -p "$BASE_WORKDIR/classes"
javac -g -d "$BASE_WORKDIR/classes" "$SAMPLE_SRC" "$CONSOLE_SRC"

# ─────────────────────────────────────────────
# Shared prompt (read from prompt.txt)
# ─────────────────────────────────────────────
PROMPT_FILE="$SCRIPT_DIR/prompt.txt"
if [[ ! -f "$PROMPT_FILE" ]]; then
  fail "prompt.txt not found: $PROMPT_FILE"
  exit 1
fi
PROMPT=$(cat "$PROMPT_FILE")

# ─────────────────────────────────────────────
# Validation function
# ─────────────────────────────────────────────
BUGS_TOTAL=5

check_bug() {
  local bug_num="$1"
  local description="$2"
  local report_lower="$3"
  shift 3
  local patterns=("$@")

  local matched=0
  for pattern in "${patterns[@]}"; do
    if echo "$report_lower" | grep -qiE "$pattern"; then
      matched=$((matched + 1))
    fi
  done

  local required=$(( ${#patterns[@]} > 2 ? 2 : 1 ))
  if [[ $matched -ge $required ]]; then
    pass "Bug $bug_num: $description ($matched/${#patterns[@]} indicators)"
    return 0
  else
    fail "Bug $bug_num: $description ($matched/${#patterns[@]} indicators)"
    return 1
  fi
}

validate_report() {
  local agent_name="$1"
  local report_file="$2"

  if [[ ! -f "$report_file" ]]; then
    fail "[$agent_name] DEBUG-REPORT.md was not created."
    return 1
  fi

  pass "[$agent_name] DEBUG-REPORT.md exists ($(wc -l < "$report_file") lines)"

  if [[ "$VERBOSE" == true ]]; then
    echo ""
    echo "--- DEBUG-REPORT.md ---"
    cat "$report_file"
    echo "--- end ---"
    echo ""
  fi

  local report_lower
  report_lower=$(tr '[:upper:]' '[:lower:]' < "$report_file")

  local bugs_found=0

  check_bug 1 "NullPointerException (null input / processMessage)" "$report_lower" \
    "nullpointerexception" "processmessage" "null" "trim" \
    && bugs_found=$((bugs_found + 1))

  check_bug 2 "Off-by-one counter error" "$report_lower" \
    "off.by.one|off-by-one|warningcount.*-.*1|count.*(minus|less|incorrect|wrong)" \
    "warningcount" "count" \
    && bugs_found=$((bugs_found + 1))

  check_bug 3 "NullPointerException after clearHistory (list set to null)" "$report_lower" \
    "clearhistory|clear.*history" "null" "warninghistory|warning.*history" \
    && bugs_found=$((bugs_found + 1))

  check_bug 4 "StringIndexOutOfBoundsException (substring)" "$report_lower" \
    "stringindexoutofboundsexception|indexoutofbounds|index.*out.*bound" \
    "substring" "short|length|bound" \
    && bugs_found=$((bugs_found + 1))

  check_bug 5 "ConsoleAppTest discount lookup fails (untrimmed input)" "$report_lower" \
    "trim|trailing.*space|whitespace|strip" \
    "discount|consoleapptest|console.*app" "premium|map.*get|lookup|0.*instead" \
    && bugs_found=$((bugs_found + 1))

  separator
  if [[ $bugs_found -eq $BUGS_TOTAL ]]; then
    pass "[$agent_name] $bugs_found/$BUGS_TOTAL bugs detected ✅"
    return 0
  elif [[ $bugs_found -ge 3 ]]; then
    warn "[$agent_name] $bugs_found/$BUGS_TOTAL bugs detected (acceptable) ⚠️"
    return 0
  else
    fail "[$agent_name] $bugs_found/$BUGS_TOTAL bugs detected ❌"
    return 1
  fi
}

# ─────────────────────────────────────────────
# Setup an isolated work directory for one agent
# ─────────────────────────────────────────────
setup_workdir() {
  local agent_name="$1"
  local workdir="$BASE_WORKDIR/$agent_name"

  mkdir -p "$workdir"

  # Compiled classes
  cp -r "$BASE_WORKDIR/classes" "$workdir/classes"

  # Plugin descriptor
  mkdir -p "$workdir/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/plugin.json" "$workdir/.claude-plugin/"

  # Agents
  cp -r "$REPO_ROOT/agents" "$workdir/agents"

  # Skill scripts
  mkdir -p "$workdir/skills/jdb-debugger/scripts"
  cp "$REPO_ROOT/skills/jdb-debugger/scripts/"*.sh "$workdir/skills/jdb-debugger/scripts/"
  chmod +x "$workdir/skills/jdb-debugger/scripts/"*.sh

  # Skill documentation
  cp "$REPO_ROOT/skills/jdb-debugger/SKILL.md" "$workdir/skills/jdb-debugger/"

  # References (if they exist)
  if [[ -d "$REPO_ROOT/skills/jdb-debugger/references" ]]; then
    cp -r "$REPO_ROOT/skills/jdb-debugger/references" "$workdir/skills/jdb-debugger/"
  fi

  # Permissions (used by claude; copilot uses --allow-all)
  mkdir -p "$workdir/.claude"
  cat > "$workdir/.claude/settings.local.json" <<'SETTINGS'
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

  echo "$workdir"
}

# ─────────────────────────────────────────────
# Run test for: Claude Code CLI
# ─────────────────────────────────────────────
run_claude() {
  local workdir
  workdir=$(setup_workdir "claude")

  start_report "claude"
  banner "Claude Code CLI" "Running"

  log "Work directory: $workdir"
  log "Model: ${MODEL:-default}"
  log "Max budget: \$${MAX_BUDGET}"

  local claude_args=(
    --print
    --plugin-dir "$workdir"
    --max-budget-usd "$MAX_BUDGET"
    --no-session-persistence
  )

  if [[ "$ALLOW_ALL" == true ]]; then
    claude_args+=(--dangerously-skip-permissions)
  fi

  if [[ "$VERBOSE" == true ]]; then
    claude_args+=(--verbose)
  fi

  if [[ -n "$MODEL" ]]; then
    claude_args+=(--model "$MODEL")
  fi

  cd "$workdir"

  if [[ "$VERBOSE" == true ]]; then
    claude "${claude_args[@]}" "$PROMPT" 2>&1 | tee "$workdir/agent-output.log"
  else
    claude "${claude_args[@]}" "$PROMPT" > "$workdir/agent-output.log" 2>&1
  fi

  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "[Claude] Agent exited with code $exit_code"
    if [[ "$VERBOSE" != true ]]; then
      echo "--- Last 30 lines of output ---"
      tail -30 "$workdir/agent-output.log"
    fi
    return 1
  fi

  log "Claude agent completed."

  banner "Claude Code CLI" "Validation"
  validate_report "Claude" "$workdir/DEBUG-REPORT.md"

  if [[ -f "$workdir/DEBUG-REPORT.md" ]]; then
    cp "$workdir/DEBUG-REPORT.md" "$RESULTS_DIR/DEBUG-REPORT-claude-${REPORT_TIMESTAMP}.md"
    log "Saved: $RESULTS_DIR/DEBUG-REPORT-claude-${REPORT_TIMESTAMP}.md"
  fi
  finish_report
}

# ─────────────────────────────────────────────
# Run test for: GitHub Copilot CLI
# ─────────────────────────────────────────────
run_copilot() {
  local workdir
  workdir=$(setup_workdir "copilot")

  start_report "copilot"
  banner "GitHub Copilot CLI" "Running"

  log "Work directory: $workdir"
  log "Model: ${MODEL:-default}"

  local copilot_args=(
    -p "$PROMPT"
    --no-ask-user
  )

  if [[ "$ALLOW_ALL" == true ]]; then
    copilot_args+=(--yolo)
  fi

  if [[ "$VERBOSE" == true ]]; then
    copilot_args+=(--log-level debug)
  fi

  if [[ -n "$MODEL" ]]; then
    copilot_args+=(--model "$MODEL")
  fi

  cd "$workdir"

  if [[ "$VERBOSE" == true ]]; then
    copilot "${copilot_args[@]}" 2>&1 | tee "$workdir/agent-output.log"
  else
    copilot "${copilot_args[@]}" > "$workdir/agent-output.log" 2>&1
  fi

  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    fail "[Copilot] Agent exited with code $exit_code"
    if [[ "$VERBOSE" != true ]]; then
      echo "--- Last 30 lines of output ---"
      tail -30 "$workdir/agent-output.log"
    fi
    return 1
  fi

  log "Copilot agent completed."

  banner "GitHub Copilot CLI" "Validation"
  validate_report "Copilot" "$workdir/DEBUG-REPORT.md"

  if [[ -f "$workdir/DEBUG-REPORT.md" ]]; then
    cp "$workdir/DEBUG-REPORT.md" "$RESULTS_DIR/DEBUG-REPORT-copilot-${REPORT_TIMESTAMP}.md"
    log "Saved: $RESULTS_DIR/DEBUG-REPORT-copilot-${REPORT_TIMESTAMP}.md"
  fi
  finish_report
}

# ═════════════════════════════════════════════
# Main: run each agent
# ═════════════════════════════════════════════
OVERALL_EXIT=0

for agent in "${AGENTS[@]}"; do
  case "$agent" in
    claude)
      run_claude  || OVERALL_EXIT=1
      ;;
    copilot)
      run_copilot || OVERALL_EXIT=1
      ;;
  esac
done

# ─────────────────────────────────────────────
# Compute timing
# ─────────────────────────────────────────────
TEST_END_EPOCH=$(date +%s)
TEST_END_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TEST_ELAPSED=$((TEST_END_EPOCH - TEST_START_EPOCH))
ELAPSED_MIN=$((TEST_ELAPSED / 60))
ELAPSED_SEC=$((TEST_ELAPSED % 60))

# ─────────────────────────────────────────────
# Final summary
# ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                  FINAL SUMMARY                   ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""

for agent in "${AGENTS[@]}"; do
  local_workdir="$BASE_WORKDIR/$agent"
  report="$local_workdir/DEBUG-REPORT.md"
  if [[ -f "$report" ]]; then
    echo -e "${GREEN}[PASS]${NC} $agent — DEBUG-REPORT.md created"
  else
    echo -e "${RED}[FAIL]${NC} $agent — DEBUG-REPORT.md missing"
  fi
done

echo ""
if [[ $OVERALL_EXIT -eq 0 ]]; then
  echo -e "${GREEN}[PASS]${NC} All agent tests passed! ✅"
else
  echo -e "${RED}[FAIL]${NC} Some agent tests failed. ❌"
fi

echo -e "${CYAN}[test]${NC} Duration: ${ELAPSED_MIN}m ${ELAPSED_SEC}s (started $TEST_START_TS, finished $TEST_END_TS)"

if [[ "$VERBOSE" == true ]]; then
  echo -e "${CYAN}[test]${NC} Work directory preserved: $BASE_WORKDIR"
fi

exit $OVERALL_EXIT
