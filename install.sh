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
