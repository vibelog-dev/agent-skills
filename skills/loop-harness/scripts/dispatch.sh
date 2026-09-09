#!/bin/bash
# Sends one instruction to a cmux pane and polls .loop/done/<Pane>.done for completion
# Usage: dispatch.sh <Pane> "<message>" [timeout-seconds]
# Exit codes: 0 DONE/PASS · 2 BLOCKED/FAIL · 124 timeout
set -euo pipefail

PANE="$1"
MSG="$2"
TIMEOUT="${3:-900}"
# .loop/ state lives in the PROJECT you run the loop in — NOT next to this
# script, which may be installed globally (~/.claude/skills/...) or per-project.
# Anchor to the git repo you're working in; override with LOOP_PROJECT_ROOT.
ROOT="${LOOP_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DONE_FILE="$ROOT/.loop/done/$PANE.done"

mkdir -p "$ROOT/.loop/done"
rm -f "$DONE_FILE"

# cmux resolves only UUIDs/refs/indexes, not pane names — map the name to its
# surface ref recorded by spawn-panes.sh in .loop/pane-config
SURFACE="$(sed -n "s/^$PANE=\(surface:[0-9][0-9]*\).*/\1/p" "$ROOT/.loop/pane-config" 2>/dev/null | tail -1)"
SURFACE="${SURFACE:-$PANE}"

# $CMUX_WORKSPACE_ID goes stale when cmux restarts; resolve the caller's
# workspace fresh each dispatch so surface refs keep working
WS="$(cmux identify 2>/dev/null | sed -n 's/.*"workspace_ref" : "\(workspace:[0-9]*\)".*/\1/p' | head -1)"
WS="${WS:-workspace:1}"

cmux send --surface "$SURFACE" --workspace "$WS" "$MSG"
sleep 0.4
cmux send-key --surface "$SURFACE" --workspace "$WS" Enter

END=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$END" ]; do
  if [ -f "$DONE_FILE" ]; then
    STATUS="$(head -1 "$DONE_FILE")"
    echo "$STATUS"
    case "$STATUS" in
      DONE*|PASS*) exit 0 ;;
      BLOCKED*|FAIL*) exit 2 ;;
      *) exit 0 ;;
    esac
  fi
  sleep 10
done

echo "TIMEOUT after ${TIMEOUT}s waiting for $PANE" >&2
cmux capture-pane --surface "$SURFACE" --workspace "$WS" --lines 80 >&2 || true
exit 124
