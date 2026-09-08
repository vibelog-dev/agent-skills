#!/bin/bash
# Spawns Builder and Verifier cmux panes with configurable CLI/model per pane
# Usage: spawn-panes.sh [builder-spec] [verifier-spec]
#   spec format: cli:model  (e.g. claude:sonnet, claude:claude-opus-4-8, codex:default, codex:gpt-5)
set -euo pipefail

BUILDER_SPEC="${1:-claude:claude-opus-4-8}"
VERIFIER_SPEC="${2:-codex:default}"
# .loop/ state lives in the PROJECT you run the loop in — NOT next to this
# script, which may be installed globally (~/.claude/skills/...) or per-project.
# Anchor to the git repo you're working in; override with LOOP_PROJECT_ROOT.
ROOT="${LOOP_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

: "${CMUX_SURFACE_ID:?ERROR: not running inside a cmux workspace}"
command -v cmux >/dev/null || { echo "ERROR: cmux CLI not found" >&2; exit 1; }

mkdir -p "$ROOT/.loop/done" "$ROOT/.loop/tasks" "$ROOT/.loop/reports" \
         "$ROOT/.loop/checklists" "$ROOT/.loop/verify"
echo "$CMUX_SURFACE_ID" > "$ROOT/.loop/main-surface"

launch_cmd() {
  local spec="$1" cli model
  cli="${spec%%:*}"
  model="${spec#*:}"
  case "$cli" in
    claude)
      echo "claude --model $model --dangerously-skip-permissions" ;;
    codex)
      if [ "$model" = "default" ]; then
        echo "codex --dangerously-bypass-approvals-and-sandbox"
      else
        echo "codex --model $model --dangerously-bypass-approvals-and-sandbox"
      fi ;;
    *)
      echo "ERROR: unknown cli '$cli' (expected claude|codex)" >&2
      return 1 ;;
  esac
}

spawn_one() {
  local name="$1" spec="$2" direction="$3" out surface cmd
  cmd="$(launch_cmd "$spec")"
  out="$(cmux new-pane --type terminal --direction "$direction")"
  surface="$(echo "$out" | grep -oE 'surface:[0-9]+' | head -1)"
  [ -n "$surface" ] || { echo "ERROR: could not parse surface from: $out" >&2; exit 1; }
  cmux rename-tab --surface "$surface" "$name"
  sleep 1
  cmux send --surface "$surface" "cd $ROOT && $cmd"
  sleep 0.4
  cmux send-key --surface "$surface" Enter
  echo "$name=$surface spec=$spec"
}

{
  echo "main=claude-opus-4-8 (current session)"
  spawn_one "Builder" "$BUILDER_SPEC" right
  spawn_one "Verifier" "$VERIFIER_SPEC" down
} | tee "$ROOT/.loop/pane-config"

echo "Waiting for CLIs to start..."
sleep 15
# cmux resolves only UUIDs/refs/indexes, not pane names — read each pane's
# surface ref back from pane-config (same mapping dispatch.sh uses)
for p in Builder Verifier; do
  ref="$(sed -n "s/^$p=\(surface:[0-9][0-9]*\).*/\1/p" "$ROOT/.loop/pane-config" | tail -1)"
  if [ -n "$ref" ] && cmux capture-pane --surface "$ref" --lines 40 | grep -qiE 'claude|codex|shortcuts|welcome'; then
    echo "$p: ready"
  else
    echo "$p: NOT READY — check the pane manually" >&2
  fi
done
