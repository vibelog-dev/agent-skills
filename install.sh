#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SKILLS_DIR:=$SCRIPT_DIR/skills}"

# skill_field <skill_dir> <field> -> prints top-level frontmatter value
skill_field() {
  local dir="$1" field="$2"
  awk -v f="$field" '
    NR==1 && $0!="---" { exit }
    NR==1 { next }
    $0=="---" { exit }
    $0 ~ "^"f":[ \t]*" { sub("^"f":[ \t]*",""); print; exit }
  ' "$dir/SKILL.md"
}

# list_skills -> names of dirs under SKILLS_DIR that contain a SKILL.md
list_skills() {
  local d
  for d in "$SKILLS_DIR"/*/; do
    [ -f "${d}SKILL.md" ] || continue
    basename "$d"
  done
}

# target_path <cli> <scope> <name> -> absolute symlink target
target_path() {
  local cli="$1" scope="$2" name="$3"
  case "$cli:$scope" in
    claude:global)  printf '%s/.claude/skills/%s\n'   "$HOME" "$name" ;;
    claude:project) printf '%s/.claude/skills/%s\n'   "$PWD"  "$name" ;;
    pi:global)      printf '%s/.pi/agent/skills/%s\n' "$HOME" "$name" ;;
    pi:project)     printf '%s/.pi/skills/%s\n'       "$PWD"  "$name" ;;
    cursor:global)  printf '%s/.cursor/skills/%s\n'   "$HOME" "$name" ;;
    cursor:project) printf '%s/.cursor/skills/%s\n'   "$PWD"  "$name" ;;
    *) return 1 ;;
  esac
}

# link_state <target> <src> -> absent|ours|foreign|real
link_state() {
  local target="$1" src="$2"
  if [ -L "$target" ]; then
    if [ "$(readlink "$target")" = "$src" ]; then echo ours; else echo foreign; fi
    return
  fi
  if [ -e "$target" ]; then echo real; return; fi
  echo absent
}

# link_skill <src> <target> <mode> ; mode: default|backup|force|dryrun
link_skill() {
  local src="$1" target="$2" mode="$3"
  local parent; parent="$(dirname "$target")"
  case "$(link_state "$target" "$src")" in
    absent)
      [ "$mode" = dryrun ] && { echo "would-link"; return; }
      mkdir -p "$parent"; ln -s "$src" "$target"; echo "linked" ;;
    ours)
      [ "$mode" = dryrun ] && { echo "would-refresh"; return; }
      mkdir -p "$parent"; ln -sfn "$src" "$target"; echo "refreshed" ;;
    foreign)
      echo "skipped-foreign" ;;
    real)
      case "$mode" in
        backup)
          local bak="${target}.bak.$(date +%Y%m%d%H%M%S)"
          mv "$target" "$bak"; ln -s "$src" "$target"; echo "backed-up:$bak" ;;
        force)
          rm -rf "$target"; ln -s "$src" "$target"; echo "forced" ;;
        dryrun)
          echo "would-skip-real" ;;
        *)
          echo "skipped-real" ;;
      esac ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Install SKILL.md skills into a coding-agent CLI as symlinks.

  --cli <claude|cursor|pi>   target CLI
  --scope <global|project>   install location
  --skills <a,b,c>           comma-separated skill names
  --all                      select every discoverable skill
  --dry-run                  show planned actions, change nothing
  --backup                   on collision, back up the existing dir then link
  --force                    on collision, replace without backup (destructive)
  --yes, -y                  assume yes to prompts
  --list                     show currently-linked skills
  --uninstall                remove only symlinks pointing at this repo
  -h, --help                 this help

Bare invocation is interactive: pick CLI, scope, then skills.
EOF
}

main() {
  set -euo pipefail
  MAIN_RAN=1
  usage
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
