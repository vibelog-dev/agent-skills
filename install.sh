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
      case "$mode" in
        backup)
          local bak="${target}.bak.$(date +%Y%m%d%H%M%S).$$"
          mv "$target" "$bak"; ln -s "$src" "$target"; echo "backed-up:$bak" ;;
        force)
          rm "$target"; ln -s "$src" "$target"; echo "forced" ;;
        dryrun)
          echo "would-skip-foreign" ;;
        *)
          echo "skipped-foreign" ;;
      esac ;;
    real)
      case "$mode" in
        backup)
          local bak="${target}.bak.$(date +%Y%m%d%H%M%S).$$"
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

# resolve_mode -> default|backup|force|dryrun from flag vars
resolve_mode() {
  if [ "${DRYRUN:-0}" = 1 ]; then echo dryrun
  elif [ "${FORCE:-0}" = 1 ]; then echo force
  elif [ "${BACKUP:-0}" = 1 ]; then echo backup
  else echo default; fi
}

# do_install <cli> <scope> <mode> <name...>
do_install() {
  local cli="$1" scope="$2" mode="$3"; shift 3
  local name src target action
  for name in "$@"; do
    src="$SKILLS_DIR/$name"
    if [ ! -f "$src/SKILL.md" ]; then
      printf '%s: skipped-missing\n' "$name"; continue
    fi
    target="$(target_path "$cli" "$scope" "$name")" || {
      printf '%s: bad-target\n' "$name"; continue; }
    action="$(link_skill "$src" "$target" "$mode")"
    printf '%s: %s\n' "$name" "$action"
  done
}

# remove_link <target> [mode] : delete only if symlink pointing under SKILLS_DIR
# mode dryrun mutates nothing and reports would-remove in place of removed
remove_link() {
  local target="$1" mode="${2:-default}"
  if [ -L "$target" ]; then
    case "$(readlink "$target")" in
      "$SKILLS_DIR"/*)
        [ "$mode" = dryrun ] && { echo "would-remove"; return; }
        rm "$target"; echo "removed"; return ;;
      *) echo "skipped-foreign"; return ;;
    esac
  fi
  [ -e "$target" ] && { echo "skipped-real"; return; }
  echo "absent"
}

# do_list <cli> <scope> : show every discoverable skill's link status
do_list() {
  local cli="$1" scope="$2" name target
  while IFS= read -r name; do
    target="$(target_path "$cli" "$scope" "$name")" || continue
    if [ "$(link_state "$target" "$SKILLS_DIR/$name")" = ours ]; then
      printf '%s: linked\n' "$name"
    else
      printf '%s: -\n' "$name"
    fi
  done < <(list_skills)
}

# do_uninstall <cli> <scope> <mode> <name...>
do_uninstall() {
  local cli="$1" scope="$2" mode="$3"; shift 3
  local name target
  for name in "$@"; do
    target="$(target_path "$cli" "$scope" "$name")" || continue
    printf '%s: %s\n' "$name" "$(remove_link "$target" "$mode")"
  done
}

# prompt_choice <varname> <prompt> <option...> : numbered single choice
prompt_choice() {
  local var="$1" prompt="$2"; shift 2
  local -a opts=("$@"); local i reply
  while :; do
    for i in "${!opts[@]}"; do printf '  %d) %s\n' "$((i+1))" "${opts[$i]}" >&2; done
    printf '%s ' "$prompt" >&2
    read -r reply || { echo "no input; aborting" >&2; exit 1; }
    if [ "$reply" -ge 1 ] 2>/dev/null && [ "$reply" -le "${#opts[@]}" ]; then
      printf -v "$var" '%s' "${opts[$((reply-1))]}"; return 0
    fi
    echo "invalid choice" >&2
  done
}

# prompt_skills_numbered : sets global array `names` from a numbered multi-select
prompt_skills_numbered() {
  local -a all=() ; local n i reply
  while IFS= read -r n; do all+=("$n"); done < <(list_skills)
  for i in "${!all[@]}"; do printf '  %d) %s\n' "$((i+1))" "${all[$i]}" >&2; done
  printf 'Select the skills to install (numbers separated by space/comma, or "all"): ' >&2
  read -r reply || { echo "no input; aborting" >&2; exit 1; }
  names=()
  if [ "$reply" = all ]; then names=("${all[@]}"); return; fi
  reply="${reply//,/ }"
  for i in $reply; do
    [ "$i" -ge 1 ] 2>/dev/null && [ "$i" -le "${#all[@]}" ] && names+=("${all[$((i-1))]}")
  done
}

# prompt_skills_tty : in-place checkbox menu; sets global array `names`
prompt_skills_tty() {
  local -a all=() checked=() ; local n i cur=0 key rest
  while IFS= read -r n; do all+=("$n"); done < <(list_skills)
  local count="${#all[@]}"
  [ "$count" -eq 0 ] && { names=(); return; }
  for i in "${!all[@]}"; do checked[$i]=0; done

  # draw the whole menu (cursor stays after the last line)
  _draw() {
    local j mark ptr
    for j in "${!all[@]}"; do
      if [ "$j" = "$cur" ]; then ptr='>'; else ptr=' '; fi
      if [ "${checked[$j]}" = 1 ]; then mark='x'; else mark=' '; fi
      printf '\033[2K%s [%s] %s\n' "$ptr" "$mark" "${all[$j]}" >&2
    done
  }

  printf '\033[?25l' >&2                       # hide cursor
  # exit in the trap: bash <4.4 restarts read after a non-exiting trap,
  # which would make the menu impossible to cancel
  trap 'printf "\033[?25h" >&2; exit 130' INT  # restore cursor on Ctrl-C
  printf 'Select skills (space to toggle, enter to confirm):\n' >&2
  _draw
  while :; do
    IFS= read -rsn1 key || { printf '\033[?25h' >&2; echo "no input; aborting" >&2; exit 1; }
    case "$key" in
      $'\x1b')
        IFS= read -rsn2 -t 1 rest
        case "$rest" in
          '[A') [ "$cur" -gt 0 ] && cur=$((cur-1)) ;;
          '[B') [ "$cur" -lt $((count-1)) ] && cur=$((cur+1)) ;;
        esac ;;
      k) [ "$cur" -gt 0 ] && cur=$((cur-1)) ;;
      j) [ "$cur" -lt $((count-1)) ] && cur=$((cur+1)) ;;
      ' ') if [ "${checked[$cur]}" = 1 ]; then checked[$cur]=0; else checked[$cur]=1; fi ;;
      a)
        local any=0
        for i in "${!all[@]}"; do [ "${checked[$i]}" = 1 ] && any=1; done
        for i in "${!all[@]}"; do [ "$any" = 1 ] && checked[$i]=0 || checked[$i]=1; done ;;
      '') break ;;   # Enter
    esac
    printf '\033[%dA' "$count" >&2             # move cursor up to menu top
    _draw
  done
  trap - INT
  printf '\033[?25h' >&2                        # restore cursor

  names=()
  for i in "${!all[@]}"; do
    [ "${checked[$i]}" = 1 ] && names+=("${all[$i]}")
  done
  unset -f _draw
}

# prompt_skills : dispatch to TTY checkbox menu or numbered fallback
prompt_skills() {
  if [ -t 0 ]; then prompt_skills_tty; else prompt_skills_numbered; fi
}

main() {
  set -euo pipefail
  MAIN_RAN=1
  local CLI="" SCOPE="" SKILLS_ARG="" ALL=0 ACTION=install
  DRYRUN=0 BACKUP=0 FORCE=0 YES=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --cli) CLI="$2"; shift 2 ;;
      --scope) SCOPE="$2"; shift 2 ;;
      --skills) SKILLS_ARG="$2"; shift 2 ;;
      --all) ALL=1; shift ;;
      --dry-run) DRYRUN=1; shift ;;
      --backup) BACKUP=1; shift ;;
      --force) FORCE=1; shift ;;
      --yes|-y) YES=1; shift ;;
      --list) ACTION=list; shift ;;
      --uninstall) ACTION=uninstall; shift ;;
      -h|--help) usage; return 0 ;;
      *) printf 'unknown option: %s\n' "$1" >&2; usage; return 2 ;;
    esac
  done

  # validate provided cli/scope up front
  if [ -n "$CLI" ]; then
    case "$CLI" in
      claude|cursor|pi) ;;
      *) printf 'invalid --cli: %s\n' "$CLI" >&2; usage; return 2 ;;
    esac
  fi
  if [ -n "$SCOPE" ]; then
    case "$SCOPE" in
      global|project) ;;
      *) printf 'invalid --scope: %s\n' "$SCOPE" >&2; usage; return 2 ;;
    esac
  fi

  # selected skill names
  local -a names=()
  if [ "$ALL" = 1 ]; then
    while IFS= read -r n; do names+=("$n"); done < <(list_skills)
  elif [ -n "$SKILLS_ARG" ]; then
    IFS=',' read -r -a names <<<"$SKILLS_ARG"
  fi
  [ -n "$CLI" ]   || prompt_choice CLI   "Select the target CLI:" claude cursor pi
  [ -n "$SCOPE" ] || prompt_choice SCOPE "Select where to install the skills:" global project
  if [ "$ACTION" != list ] && [ "$ALL" != 1 ] && [ -z "$SKILLS_ARG" ] && [ "${#names[@]}" -eq 0 ]; then
    prompt_skills
  fi

  if [ "$ACTION" != list ] && [ "${#names[@]}" -eq 0 ]; then
    echo "no skills selected" >&2; return 1
  fi

  local mode; mode="$(resolve_mode)"
  case "$ACTION" in
    list)      do_list "$CLI" "$SCOPE" ;;
    uninstall) do_uninstall "$CLI" "$SCOPE" "$mode" ${names[@]+"${names[@]}"} ;;
    *)         do_install "$CLI" "$SCOPE" "$mode" ${names[@]+"${names[@]}"} ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
