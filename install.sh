#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SKILLS_DIR:=$SCRIPT_DIR/skills}"

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
