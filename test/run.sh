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

  # foreign symlink force -> forced, replaced with link to src
  t7="$tdir/g"; ln -s "$ls_dir/somewhere-else" "$t7"
  assert_eq "foreign force->forced" "forced" "$(link_skill "$src" "$t7" force)"
  assert_true "g now symlink" test -L "$t7"
  assert_eq "g points at src" "$src" "$(readlink "$t7")"

  # foreign symlink backup -> backed-up:<path>, old link preserved as backup, target relinked
  t8="$tdir/h"; ln -s "$ls_dir/somewhere-else" "$t8"
  out="$(link_skill "$src" "$t8" backup)"
  assert_true "foreign backup prefix" grep -q '^backed-up:' <<<"$out"
  bak="${out#backed-up:}"
  assert_true "foreign backup is symlink" test -L "$bak"
  assert_eq "foreign backup points at old dest" "$ls_dir/somewhere-else" "$(readlink "$bak")"
  assert_true "h now symlink" test -L "$t8"
  assert_eq "h points at src" "$src" "$(readlink "$t8")"

  # foreign symlink dryrun -> would-skip-foreign, untouched
  t9="$tdir/i"; ln -s "$ls_dir/somewhere-else" "$t9"
  assert_eq "foreign dryrun" "would-skip-foreign" "$(link_skill "$src" "$t9" dryrun)"
  assert_eq "i untouched" "$ls_dir/somewhere-else" "$(readlink "$t9")"

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

# Task 8 (Bug 1): --uninstall --dry-run must not delete links
i8="$(mktemp -d)"; home8="$(mktemp -d)"
mkdir -p "$i8/skills/alpha"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i8/skills/alpha/SKILL.md"
HOME="$home8" SKILLS_DIR="$i8/skills" bash "$ROOT/install.sh" --cli claude --scope global --all >/dev/null
dry8="$(HOME="$home8" SKILLS_DIR="$i8/skills" bash "$ROOT/install.sh" --cli claude --scope global --all --uninstall --dry-run)"
assert_true "dry-run uninstall says would-remove" grep -q 'alpha: would-remove' <<<"$dry8"
assert_true "dry-run kept the symlink" test -L "$home8/.claude/skills/alpha"
# real uninstall then removes it
real8="$(HOME="$home8" SKILLS_DIR="$i8/skills" bash "$ROOT/install.sh" --cli claude --scope global --all --uninstall)"
assert_true "real uninstall removed alpha" grep -q 'alpha: removed' <<<"$real8"
assert_false "alpha symlink gone after real uninstall" test -L "$home8/.claude/skills/alpha"
rm -rf "$i8" "$home8"

# Task 9 (Bug 2): bare --uninstall must prompt for skills; --list stays prompt-free
i9="$(mktemp -d)"; home9="$(mktemp -d)"
mkdir -p "$i9/skills/alpha"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i9/skills/alpha/SKILL.md"
HOME="$home9" SKILLS_DIR="$i9/skills" bash "$ROOT/install.sh" --cli claude --scope global --all >/dev/null
# bare --uninstall: prompts CLI (1=claude), scope (1=global), skills (1=alpha)
uno9="$(printf '1\n1\n1\n' | HOME="$home9" SKILLS_DIR="$i9/skills" bash "$ROOT/install.sh" --uninstall)"
assert_true "bare uninstall removed a skill" grep -q ': removed' <<<"$uno9"
assert_false "alpha symlink gone after bare uninstall" test -L "$home9/.claude/skills/alpha"
# --list must remain non-interactive (no skills prompt) even with stdin closed
HOME="$home9" SKILLS_DIR="$i9/skills" bash "$ROOT/install.sh" --cli claude --scope global --list < /dev/null >/dev/null 2>&1
assert_eq "list exits 0 with no stdin" "0" "$?"
rm -rf "$i9" "$home9"

# Task 10: non-TTY stdin uses the numbered fallback (prompt text appears on stderr)
i10="$(mktemp -d)"; home10="$(mktemp -d)"
mkdir -p "$i10/skills/alpha" "$i10/skills/beta"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i10/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: b\n---\n'  > "$i10/skills/beta/SKILL.md"
err10="$(printf '1\n1\n1\n' | HOME="$home10" SKILLS_DIR="$i10/skills" bash "$ROOT/install.sh" 2>&1 >/dev/null)"
assert_true "piped stdin uses numbered fallback" grep -q 'Select the skills to install' <<<"$err10"
assert_true "numbered fallback still links first skill" test -L "$home10/.claude/skills/alpha"
rm -rf "$i10" "$home10"

# Task 11: interactive invalid choice re-prompts instead of aborting
i11="$(mktemp -d)"; home11="$(mktemp -d)"
mkdir -p "$i11/skills/alpha"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i11/skills/alpha/SKILL.md"
# 'banana' is invalid at the CLI prompt -> re-prompt; then 1=claude, 1=global, 1=alpha
rec="$(printf 'banana\n1\n1\n1\n' | HOME="$home11" SKILLS_DIR="$i11/skills" bash "$ROOT/install.sh" 2>/dev/null)"; rc=$?
assert_eq "invalid choice recovers (exit 0)" "0" "$rc"
assert_true "recovered run links alpha" grep -q 'alpha: linked' <<<"$rec"
assert_true "alpha symlink exists after recovery" test -L "$home11/.claude/skills/alpha"
rm -rf "$i11" "$home11"

# Task 12: EOF on stdin -> controlled abort (nonzero exit + message)
eoferr="$(bash "$ROOT/install.sh" < /dev/null 2>&1)"; rc=$?
assert_true "EOF exits nonzero" test "$rc" -ne 0
assert_true "EOF prints abort message" grep -q 'no input; aborting' <<<"$eoferr"

# Task 13: bad --cli -> exit 2, names the value, no bad-target on stdout
errf="$(mktemp)"
outcli="$(bash "$ROOT/install.sh" --cli foo --scope global --all 2>"$errf")"; rc=$?
assert_eq "bad --cli exits 2" "2" "$rc"
assert_true "bad --cli mentions foo" grep -q 'foo' "$errf"
assert_false "bad --cli no bad-target on stdout" grep -q 'bad-target' <<<"$outcli"
rm -f "$errf"

# Task 14: bad --scope -> exit 2, names the value
errf="$(mktemp)"
bash "$ROOT/install.sh" --cli claude --scope bar --all >/dev/null 2>"$errf"; rc=$?
assert_eq "bad --scope exits 2" "2" "$rc"
assert_true "bad --scope mentions bar" grep -q 'bar' "$errf"
rm -f "$errf"

# Task 15: empty skill selection -> nonzero exit + message
i15="$(mktemp -d)"; home15="$(mktemp -d)"
mkdir -p "$i15/skills/alpha"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$i15/skills/alpha/SKILL.md"
errf="$(mktemp)"
printf '1\n1\n\n' | HOME="$home15" SKILLS_DIR="$i15/skills" bash "$ROOT/install.sh" >/dev/null 2>"$errf"; rc=$?
assert_true "empty selection exits nonzero" test "$rc" -ne 0
assert_true "empty selection message" grep -q 'no skills selected' "$errf"
rm -f "$errf"; rm -rf "$i15" "$home15"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
