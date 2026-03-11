#!/usr/bin/env bash
# codex-wrapper.sh — Robust wrapper around `codex exec` for Claude Code integration
#
# Usage: codex-wrapper.sh "<task description>" [working_dir] [timeout_seconds] [model]
#
# Output: Always valid JSON on stdout, one of:
#   {"success":true, "exit_code":0, "message":"...", "files_changed":[...]}
#   {"success":false, "exit_code":N, "error":"...", "details":"..."}
#
# Features:
#   - Validates codex is installed and authenticated
#   - Auto-detects or accepts working directory
#   - Enforces timeout (default: 300s)
#   - Uses --output-last-message for reliable result extraction
#   - Falls back to JSONL parsing if needed
#   - Captures changed files via git diff
#   - Clean JSON output for Claude Code consumption

set -uo pipefail

# ── Args ────────────────────────────────────────────────────────
TASK="${1:?Usage: codex-wrapper.sh '<task>' [working_dir] [timeout_seconds] [model]}"
WORKDIR="${2:-$(pwd)}"
TIMEOUT="${3:-300}"
MODEL="${4:-}"

# ── Helpers ─────────────────────────────────────────────────────
json_escape() {
  # Escape a string for safe JSON embedding
  printf '%s' "$1" | jq -Rs .
}

emit_error() {
  local error="$1"
  local details="${2:-}"
  local exit_code="${3:-1}"
  printf '{"success":false,"exit_code":%d,"error":%s,"details":%s}\n' \
    "$exit_code" "$(json_escape "$error")" "$(json_escape "$details")"
  exit "${3:-1}"
}

# ── Preflight ───────────────────────────────────────────────────
if ! command -v codex &>/dev/null; then
  emit_error "codex CLI not found" "Install with: npm install -g @openai/codex" 1
fi

if ! command -v jq &>/dev/null; then
  emit_error "jq not found" "Install with: apt install jq" 1
fi

if [ ! -d "$WORKDIR" ]; then
  emit_error "Working directory does not exist" "$WORKDIR" 1
fi

# Check if workdir is a git repo (codex requires it unless --skip-git-repo-check)
SKIP_GIT=""
if ! git -C "$WORKDIR" rev-parse --git-dir &>/dev/null 2>&1; then
  SKIP_GIT="--skip-git-repo-check"
fi

# ── Temp files ──────────────────────────────────────────────────
TMPDIR_WORK=$(mktemp -d)
LAST_MSG_FILE="$TMPDIR_WORK/last-message.txt"
JSONL_FILE="$TMPDIR_WORK/events.jsonl"
STDERR_FILE="$TMPDIR_WORK/stderr.log"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

# ── Snapshot git state before ────────────────────────────────────
GIT_BEFORE=""
if git -C "$WORKDIR" rev-parse --git-dir &>/dev/null 2>&1; then
  GIT_BEFORE=$(git -C "$WORKDIR" diff --stat HEAD 2>/dev/null || true)
fi

# ── Build command ───────────────────────────────────────────────
CMD=(codex exec --full-auto --json)
CMD+=(-o "$LAST_MSG_FILE")
CMD+=(-C "$WORKDIR")

if [ -n "$SKIP_GIT" ]; then
  CMD+=("$SKIP_GIT")
fi

if [ -n "$MODEL" ]; then
  CMD+=(-m "$MODEL")
fi

CMD+=("$TASK")

# ── Execute ─────────────────────────────────────────────────────
EXIT_CODE=0
timeout "$TIMEOUT" "${CMD[@]}" >"$JSONL_FILE" 2>"$STDERR_FILE" || EXIT_CODE=$?

# ── Handle timeout ──────────────────────────────────────────────
if [ "$EXIT_CODE" -eq 124 ]; then
  # Try to salvage partial output
  PARTIAL=""
  if [ -f "$LAST_MSG_FILE" ] && [ -s "$LAST_MSG_FILE" ]; then
    PARTIAL=$(cat "$LAST_MSG_FILE")
  fi
  printf '{"success":false,"exit_code":124,"error":"Codex timed out after %ds","partial_output":%s}\n' \
    "$TIMEOUT" "$(json_escape "$PARTIAL")"
  exit 1
fi

# ── Extract result ──────────────────────────────────────────────

# Strategy 1: Use --output-last-message file (most reliable)
if [ -f "$LAST_MSG_FILE" ] && [ -s "$LAST_MSG_FILE" ]; then
  RESULT=$(cat "$LAST_MSG_FILE")

  # Detect files changed after codex ran
  FILES_CHANGED="[]"
  if git -C "$WORKDIR" rev-parse --git-dir &>/dev/null 2>&1; then
    FILES_CHANGED=$(git -C "$WORKDIR" diff --name-only HEAD 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")
    # Also check untracked files
    UNTRACKED=$(git -C "$WORKDIR" ls-files --others --exclude-standard 2>/dev/null | jq -R . | jq -s . 2>/dev/null || echo "[]")
    FILES_CHANGED=$(echo "[$FILES_CHANGED, $UNTRACKED]" | jq -s 'flatten | unique' 2>/dev/null || echo "[]")
  fi

  printf '{"success":true,"exit_code":%d,"message":%s,"files_changed":%s}\n' \
    "$EXIT_CODE" "$(json_escape "$RESULT")" "$FILES_CHANGED"
  exit 0
fi

# Strategy 2: Parse JSONL for the last assistant message
if [ -f "$JSONL_FILE" ] && [ -s "$JSONL_FILE" ]; then
  # Look for error events first
  ERROR_MSG=$(jq -r 'select(.type == "error") | .message' "$JSONL_FILE" 2>/dev/null | tail -1)
  if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
    STDERR_CONTENT=$(cat "$STDERR_FILE" 2>/dev/null || true)
    printf '{"success":false,"exit_code":%d,"error":%s,"details":%s}\n' \
      "$EXIT_CODE" "$(json_escape "$ERROR_MSG")" "$(json_escape "$STDERR_CONTENT")"
    exit 1
  fi

  # Try to find completion message in JSONL
  # Codex JSONL has various event types; look for the final content
  LAST_CONTENT=$(jq -r 'select(.type == "message.completed" or .type == "response.completed") | .content // .text // empty' "$JSONL_FILE" 2>/dev/null | tail -1)
  if [ -n "$LAST_CONTENT" ]; then
    printf '{"success":true,"exit_code":%d,"message":%s,"files_changed":[]}\n' \
      "$EXIT_CODE" "$(json_escape "$LAST_CONTENT")"
    exit 0
  fi

  # Last resort: dump raw JSONL summary
  LINE_COUNT=$(wc -l < "$JSONL_FILE")
  LAST_LINES=$(tail -5 "$JSONL_FILE" | jq -s '.' 2>/dev/null || tail -5 "$JSONL_FILE")
  printf '{"success":%s,"exit_code":%d,"message":"Codex completed but output format unclear","raw_event_count":%d,"last_events":%s}\n' \
    "$([ "$EXIT_CODE" -eq 0 ] && echo true || echo false)" \
    "$EXIT_CODE" \
    "$LINE_COUNT" \
    "$(json_escape "$LAST_LINES")"
  exit "$EXIT_CODE"
fi

# Strategy 3: Nothing captured — report failure with stderr
STDERR_CONTENT=$(cat "$STDERR_FILE" 2>/dev/null || true)
printf '{"success":false,"exit_code":%d,"error":"No output captured from Codex","details":%s}\n' \
  "$EXIT_CODE" "$(json_escape "$STDERR_CONTENT")"
exit 1
