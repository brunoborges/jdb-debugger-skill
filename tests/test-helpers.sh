#!/usr/bin/env bash
# test-helpers.sh — Shared functions for prepare-test.sh and run-test.sh.
#
# Sourced by both scripts. Expects REPO_ROOT and SCRIPT_DIR to be set
# by the caller before sourcing.

# --- Sample files to compile ---
SAMPLE_FILES=(
  "WarningAppTest.java"
  "ConsoleAppTest.java"
  "AliasingCorruptionTest.java"
  "ClassLoaderConflictTest.java"
  "ThreadTest.java"
  "VisibilityTest.java"
)

# --- Claude permissions ---
CLAUDE_PERMISSIONS='{
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
}'

# check_javac — Fail fast if javac is missing.
check_javac() {
  if ! command -v javac &>/dev/null; then
    echo "javac not found. Install a JDK." >&2
    exit 1
  fi
}

# resolve_sources — Populate SOURCE_PATHS from SAMPLE_FILES.
resolve_sources() {
  SOURCE_PATHS=()
  for sample in "${SAMPLE_FILES[@]}"; do
    local src="$REPO_ROOT/tests/scenarios/$sample"
    if [[ ! -f "$src" ]]; then
      echo "Sample source not found: $src" >&2
      exit 1
    fi
    SOURCE_PATHS+=("$src")
  done
}

# compile_samples OUTDIR — Compile sample .java files into OUTDIR/classes.
compile_samples() {
  local outdir="$1"
  mkdir -p "$outdir/classes"
  javac -g -d "$outdir/classes" "${SOURCE_PATHS[@]}"
}

# install_plugin WORKDIR — Copy plugin descriptor, agents, skills, and
# permissions into WORKDIR/.claude (and .claude-plugin).
install_plugin() {
  local workdir="$1"

  # Plugin descriptor
  mkdir -p "$workdir/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/plugin.json" "$workdir/.claude-plugin/"

  # Agents and skills under .claude
  mkdir -p "$workdir/.claude"
  cp -r "$REPO_ROOT/agents" "$workdir/.claude/agents"

  mkdir -p "$workdir/.claude/skills/jdb-debugger/scripts"
  cp "$REPO_ROOT/skills/jdb-debugger/scripts/"*.sh "$workdir/.claude/skills/jdb-debugger/scripts/"
  chmod +x "$workdir/.claude/skills/jdb-debugger/scripts/"*.sh

  cp "$REPO_ROOT/skills/jdb-debugger/SKILL.md" "$workdir/.claude/skills/jdb-debugger/"

  if [[ -d "$REPO_ROOT/skills/jdb-debugger/references" ]]; then
    cp -r "$REPO_ROOT/skills/jdb-debugger/references" "$workdir/.claude/skills/jdb-debugger/"
  fi
}

# install_permissions WORKDIR — Write Claude permissions file.
install_permissions() {
  local workdir="$1"
  mkdir -p "$workdir/.claude"
  echo "$CLAUDE_PERMISSIONS" > "$workdir/.claude/settings.local.json"
}

# make_temp_dir — Create and print a temporary jdb-test directory.
make_temp_dir() {
  local _tmpbase="${TMPDIR:-/tmp}"
  mktemp -d "${_tmpbase%/}/jdb-test-XXXXXX"
}
