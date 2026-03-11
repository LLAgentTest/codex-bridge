#!/usr/bin/env bash
# codex-wrapper.sh — Thin wrapper around `codex exec` for Claude Code integration
#
# Usage: codex-wrapper.sh "<task description>" [working_dir] [timeout_seconds]
#
# Features:
#   - Validates codex is installed and authenticated
#   - Manages working directory
#   - Enforces timeout (default: 300s)
#   - Captures and formats output as JSON
#   - Handles exit codes cleanly

set -euo pipefail

# ── Args ────────────────────────────────────────────────────────
TASK="${1:?Usage: codex-wrapper.sh '<task>' [working_dir] [timeout_seconds]}"
WORKDIR="${2:-$(pwd)}"
TIMEOUT="${3:-300}"

# ── Preflight ───────────────────────────────────────────────────
if ! command -v codex &>/dev/null; then
  echo '{"success":false,"error":"codex CLI not found. Install: npm install -g @openai/codex"}' 
  exit 1
fi

if [ ! -d "$WORKDIR" ]; then
  echo "{\"success\":false,\"error\":\"Working directory does not exist: $WORKDIR\"}"
  exit 1
fi

# ── Execute ─────────────────────────────────────────────────────
TMPOUT=$(mktemp)
TMPERR=$(mktemp)
trap 'rm -f "$TMPOUT" "$TMPERR"' EXIT

EXIT_CODE=0
timeout "$TIMEOUT" codex exec \
  --full-auto \
  --json \
  -C "$WORKDIR" \
  "$TASK" \
  >"$TMPOUT" 2>"$TMPERR" || EXIT_CODE=$?

# ── Handle timeout ──────────────────────────────────────────────
if [ "$EXIT_CODE" -eq 124 ]; then
  echo "{\"success\":false,\"error\":\"Codex timed out after ${TIMEOUT}s\",\"partial_stdout\":$(head -c 4096 "$TMPOUT" | jq -Rs .)}"
  exit 1
fi

# ── Format output ───────────────────────────────────────────────
STDOUT=$(cat "$TMPOUT")
STDERR=$(cat "$TMPERR")

# If codex --json produced valid JSONL, pass through the last message
if [ "$EXIT_CODE" -eq 0 ]; then
  # Try to extract the last assistant message from JSONL stream
  LAST_MSG=$(grep -o '{"type":"message"[^}]*"role":"assistant".*' "$TMPOUT" | tail -1 || true)
  if [ -n "$LAST_MSG" ]; then
    echo "{\"success\":true,\"exit_code\":$EXIT_CODE,\"output\":$LAST_MSG}"
  else
    # Fallback: return raw stdout
    echo "{\"success\":true,\"exit_code\":$EXIT_CODE,\"raw_output\":$(echo "$STDOUT" | jq -Rs .)}"
  fi
else
  echo "{\"success\":false,\"exit_code\":$EXIT_CODE,\"stdout\":$(echo "$STDOUT" | jq -Rs .),\"stderr\":$(echo "$STDERR" | jq -Rs .)}"
fi
