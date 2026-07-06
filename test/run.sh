#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0
assert_eq() { # msg expected actual
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$1" "$2" "$3"; fi
}
assert_true()  { local m="$1"; shift; if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL(true): %s\n' "$m"; fi; }
assert_false() { local m="$1"; shift; if "$@"; then FAIL=$((FAIL+1)); printf 'FAIL(false): %s\n' "$m"; else PASS=$((PASS+1)); fi; }

# shellcheck disable=SC1091
source "$ROOT/install.sh"

# Task 1: help + guard
help_out="$(bash "$ROOT/install.sh" --help)"
assert_true "help mentions usage" grep -qi 'usage' <<<"$help_out"
assert_true "sourcing did not run main (no install output)" test -z "${MAIN_RAN:-}"

# Task 2: discovery — use an isolated fixture skills dir
fix="$(mktemp -d)"
mkdir -p "$fix/alpha" "$fix/beta" "$fix/notaskill"
cat >"$fix/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: Does the alpha thing.
---
body
EOF
cat >"$fix/beta/SKILL.md" <<'EOF'
---
name: beta
description: Does beta.
---
EOF
# notaskill has no SKILL.md
( SKILLS_DIR="$fix"; source "$ROOT/install.sh"
  assert_eq "field name"  "alpha"            "$(skill_field "$fix/alpha" name)"
  assert_eq "field desc"  "Does the alpha thing." "$(skill_field "$fix/alpha" description)"
  assert_eq "list skips non-skill" "alpha
beta" "$(list_skills | sort)"
  printf '%d %d\n' "$PASS" "$FAIL" > "$fix/counts" )
read -r sp sf < "$fix/counts"; PASS=$((PASS+sp)); FAIL=$((FAIL+sf))
rm -rf "$fix"

# Task 3: target_path (override HOME + cd so paths are deterministic)
th="$(mktemp -d)"; tp="$(mktemp -d)"
( HOME="$th"; cd "$tp"; source "$ROOT/install.sh"
  assert_eq "claude global" "$th/.claude/skills/x"    "$(target_path claude global x)"
  assert_eq "claude project" "$tp/.claude/skills/x"   "$(target_path claude project x)"
  assert_eq "pi global"      "$th/.pi/agent/skills/x" "$(target_path pi global x)"
  assert_eq "pi project"     "$tp/.pi/skills/x"       "$(target_path pi project x)"
  assert_eq "cursor global"  "$th/.cursor/skills/x"   "$(target_path cursor global x)"
  assert_eq "cursor project" "$tp/.cursor/skills/x"   "$(target_path cursor project x)"
  assert_false "unknown pair returns nonzero" target_path bogus global x
  printf '%d %d\n' "$PASS" "$FAIL" > "$th/counts" )
read -r sp sf < "$th/counts"; PASS=$((PASS+sp)); FAIL=$((FAIL+sf))
rm -rf "$th" "$tp"

# Task 4: link state-machine
ls_dir="$(mktemp -d)"
( source "$ROOT/install.sh"
  src="$ls_dir/repo/alpha"; mkdir -p "$src"
  tdir="$ls_dir/targets"; mkdir -p "$tdir"

  # absent -> linked, and it is a symlink to src
  t="$tdir/a"
  assert_eq "absent->linked" "linked" "$(link_skill "$src" "$t" default)"
  assert_true "a is symlink" test -L "$t"
  assert_eq "a points at src" "$src" "$(readlink "$t")"

  # ours -> refreshed (idempotent)
  assert_eq "ours->refreshed" "refreshed" "$(link_skill "$src" "$t" default)"
  assert_true "a still symlink" test -L "$t"

  # foreign symlink -> skipped, untouched
  t2="$tdir/b"; ln -s "$ls_dir/somewhere-else" "$t2"
  assert_eq "foreign->skip" "skipped-foreign" "$(link_skill "$src" "$t2" default)"
  assert_eq "b untouched" "$ls_dir/somewhere-else" "$(readlink "$t2")"

  # real dir default -> skipped, dir intact
  t3="$tdir/c"; mkdir -p "$t3"; touch "$t3/keep"
  assert_eq "real default->skip" "skipped-real" "$(link_skill "$src" "$t3" default)"
  assert_true "c still real dir" test -d "$t3"
  assert_true "c contents intact" test -f "$t3/keep"

  # real dir backup -> backed-up:<path>, original moved, symlink created
  t4="$tdir/d"; mkdir -p "$t4"; touch "$t4/keep"
  out="$(link_skill "$src" "$t4" backup)"
  assert_true "backup action prefix" grep -q '^backed-up:' <<<"$out"
  bak="${out#backed-up:}"
  assert_true "backup dir exists" test -f "$bak/keep"
  assert_true "d now symlink" test -L "$t4"
  assert_eq "d points at src" "$src" "$(readlink "$t4")"

  # real dir force -> forced, replaced, no backup
  t5="$tdir/e"; mkdir -p "$t5"; touch "$t5/keep"
  assert_eq "force->forced" "forced" "$(link_skill "$src" "$t5" force)"
  assert_true "e now symlink" test -L "$t5"

  # dryrun -> would-*, nothing created
  t6="$tdir/f"
  assert_eq "dryrun absent" "would-link" "$(link_skill "$src" "$t6" dryrun)"
  assert_false "f not created" test -e "$t6"

  printf '%d %d\n' "$PASS" "$FAIL" > "$ls_dir/counts" )
read -r sp sf < "$ls_dir/counts"; PASS=$((PASS+sp)); FAIL=$((FAIL+sf))
rm -rf "$ls_dir"

# Task 5: non-interactive install via CLI flags
i5="$(mktemp -d)"
mkdir -p "$i5/skills/alpha" "$i5/skills/beta"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i5/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: b\n---\n'  > "$i5/skills/beta/SKILL.md"
home5="$(mktemp -d)"
# non-interactive: install alpha only, claude global
out="$(HOME="$home5" SKILLS_DIR="$i5/skills" bash "$ROOT/install.sh" \
        --cli claude --scope global --skills alpha)"
assert_true "reports alpha linked" grep -q 'alpha: linked' <<<"$out"
assert_true "alpha symlink exists" test -L "$home5/.claude/skills/alpha"
assert_false "beta not installed" test -e "$home5/.claude/skills/beta"
assert_eq "alpha -> repo src" "$i5/skills/alpha" "$(readlink "$home5/.claude/skills/alpha")"

# --all installs both; --dry-run changes nothing
home5b="$(mktemp -d)"
out2="$(HOME="$home5b" SKILLS_DIR="$i5/skills" bash "$ROOT/install.sh" \
         --cli pi --scope global --all --dry-run)"
assert_true "dry-run says would-link alpha" grep -q 'alpha: would-link' <<<"$out2"
assert_false "dry-run created nothing" test -e "$home5b/.pi/agent/skills/alpha"
rm -rf "$i5" "$home5" "$home5b"

# Task 6: interactive selection driven by piped stdin
i6="$(mktemp -d)"; home6="$(mktemp -d)"
mkdir -p "$i6/skills/alpha" "$i6/skills/beta"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i6/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: b\n---\n'  > "$i6/skills/beta/SKILL.md"
# stdin lines: CLI choice (1=claude), scope choice (1=global), skills (1 = alpha)
out6="$(printf '1\n1\n1\n' | HOME="$home6" SKILLS_DIR="$i6/skills" bash "$ROOT/install.sh")"
assert_true "interactive linked alpha" grep -q 'alpha: linked' <<<"$out6"
assert_true "alpha symlink exists" test -L "$home6/.claude/skills/alpha"
assert_false "beta not selected" test -e "$home6/.claude/skills/beta"
rm -rf "$i6" "$home6"

# Task 7: list + uninstall
i7="$(mktemp -d)"; home7="$(mktemp -d)"
mkdir -p "$i7/skills/alpha"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i7/skills/alpha/SKILL.md"
# install then list
HOME="$home7" SKILLS_DIR="$i7/skills" bash "$ROOT/install.sh" --cli claude --scope global --all >/dev/null
lst="$(HOME="$home7" SKILLS_DIR="$i7/skills" bash "$ROOT/install.sh" --cli claude --scope global --list)"
assert_true "list shows alpha linked" grep -q 'alpha: linked' <<<"$lst"
# uninstall removes our symlink only
uno="$(HOME="$home7" SKILLS_DIR="$i7/skills" bash "$ROOT/install.sh" --cli claude --scope global --all --uninstall)"
assert_true "uninstall removed alpha" grep -q 'alpha: removed' <<<"$uno"
assert_false "alpha symlink gone" test -L "$home7/.claude/skills/alpha"
# uninstall refuses a real dir
mkdir -p "$home7/.claude/skills/alpha"
uno2="$(HOME="$home7" SKILLS_DIR="$i7/skills" bash "$ROOT/install.sh" --cli claude --scope global --all --uninstall)"
assert_true "uninstall skips real dir" grep -q 'alpha: skipped-real' <<<"$uno2"
assert_true "real dir still there" test -d "$home7/.claude/skills/alpha"
rm -rf "$i7" "$home7"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
