# SPDX-License-Identifier: MIT
# Copyright (c) 2020-2026 Jürgen Thelen

setopt prompt_subst

typeset -g __cmd_start=''
typeset -g __empty_accept=0
typeset -g __last_status=0
typeset -g __last_timer=''

typeset -g PWD_PROMPT=''
typeset -g GIT_PROMPT=''
typeset -g GIT_PROMPT_PLAIN=''
typeset -g PROMPT_LINE1=''
typeset -g PROMPT_LINE2=''

typeset -gA XTERM_COLORS=(
  Green 2
  DarkGreen 22
  DeepSkyBlue3 31
  DeepSkyBlue2 38
  DarkRed 52
  MediumPurple3 98
  Red3 160
  DarkOrange3 166
  Orange1 214
  Grey100 231
  Grey19 236
  Grey82 252
)

: ${COLOR_PATH_FG:=Grey82}
: ${COLOR_PATH_BG:=Grey19}
: ${COLOR_RIGHT_BG:=Grey19}
: ${COLOR_RIGHT_FG:=Grey82}
: ${COLOR_PROMPT_FG:=Grey100}
: ${COLOR_PROMPT_BG:=DeepSkyBlue2}
: ${COLOR_BRANCH_DETACHED:=MediumPurple3}
: ${COLOR_BEHIND:=Grey82}
: ${COLOR_AHEAD:=Grey82}
: ${COLOR_STAGED:=Green}
: ${COLOR_CONFLICT:=Red3}
: ${COLOR_CHANGED:=DarkOrange3}
: ${COLOR_UNTRACKED:=Orange1}
: ${COLOR_STASHED:=DeepSkyBlue3}
: ${COLOR_TIMER_BG:=DarkGreen}
: ${COLOR_TIMER_FG:=Grey100}
: ${COLOR_EXIT_BG:=DarkRed}
: ${COLOR_EXIT_FG:=Grey100}
: ${SHOW_HOSTNAME:=0}
: ${SHOW_USERNAME:=1}
: ${SHOW_PRIVILEGE_CHAR:=0}
: ${SHOW_TIMER:=1}
: ${SHOW_EXITCODE:=1}

__color() {
  local name=$1
  print -r -- "${XTERM_COLORS[$name]:-$name}"
}

__format_elapsed() {
  local total=$1
  local hours=$(( total / 3600 ))
  local mins=$(( (total % 3600) / 60 ))
  local secs=$(( total % 60 ))

  printf '%02d:%02d:%02d' "$hours" "$mins" "$secs"
}

__short_pwd() {
  local path="${PWD/#$HOME/~}"
  local -a parts

  parts=("${(@s:/:)path}")
  if (( ${#parts} > 5 )); then
    print -r -- "...  ${(j:  :)parts[-5,-1]}"
  else
    print -r -- "${path//\//  }"
  fi
}

__prompt_identity() {
  local text=''

  (( SHOW_USERNAME )) && text='%n'
  if (( SHOW_HOSTNAME )); then
    [[ -n $text ]] && text+='@%m' || text='%m'
  fi
  (( SHOW_PRIVILEGE_CHAR )) && text+=' %#'

  print -r -- "$text"
}

__git_stash_count() {
  local -a stashes
  stashes=("${(@f)$(git stash list --format='%gd' 2>/dev/null)}")
  print -r -- "${#stashes}"
}

__git_prompt() {
  GIT_PROMPT=''
  GIT_PROMPT_PLAIN=''

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return

  local -a lines parts parts_plain
  local line branch branch_oid ahead behind staged changed conflicts untracked stashes detached
  local c_right_bg c_right_fg c_branch c_branch_detached c_behind c_ahead c_staged c_conflict c_changed c_untracked c_stashed

  lines=("${(@f)$(git status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null)}")
  branch=''
  branch_oid=''
  ahead=0
  behind=0
  staged=0
  changed=0
  conflicts=0
  untracked=0
  detached=0

  for line in "${lines[@]}"; do
    case "$line" in
      '# branch.head '*)
        branch="${line#\# branch.head }"
        ;;
      '# branch.oid '*)
        branch_oid="${line#\# branch.oid }"
        ;;
      '# branch.ab '*)
        ahead="${${line#\# branch.ab +}%% *}"
        behind="${${line#* -}%% *}"
        ;;
      '1 '*|'2 '*)
        [[ ${line[3]} != '.' ]] && (( staged++ ))
        [[ ${line[4]} != '.' ]] && (( changed++ ))
        ;;
      'u '*)
        (( conflicts++ ))
        ;;
      '? '*)
        (( untracked++ ))
        ;;
    esac
  done

  if ! git symbolic-ref -q HEAD >/dev/null 2>&1 || [[ -z $branch || $branch == '(detached)' ]]; then
    detached=1
    branch="HEAD@${branch_oid:0:7}"
  fi

  stashes=$(__git_stash_count)

  c_right_bg=$(__color "$COLOR_RIGHT_BG")
  c_right_fg=$(__color "$COLOR_RIGHT_FG")
  c_branch_detached=$(__color "$COLOR_BRANCH_DETACHED")
  c_behind=$(__color "$COLOR_BEHIND")
  c_ahead=$(__color "$COLOR_AHEAD")
  c_staged=$(__color "$COLOR_STAGED")
  c_conflict=$(__color "$COLOR_CONFLICT")
  c_changed=$(__color "$COLOR_CHANGED")
  c_untracked=$(__color "$COLOR_UNTRACKED")
  c_stashed=$(__color "$COLOR_STASHED")

  c_branch=$c_right_fg
  (( detached )) && c_branch=$c_branch_detached

  (( behind > 0 )) && { parts+=("%F{${c_behind}}↓ ${behind}%f"); parts_plain+=("↓ ${behind}"); }
  (( ahead > 0 )) && { parts+=("%F{${c_ahead}}↑ ${ahead}%f"); parts_plain+=("↑ ${ahead}"); }
  (( staged > 0 )) && { parts+=("%F{${c_staged}}● ${staged}%f"); parts_plain+=("● ${staged}"); }
  (( conflicts > 0 )) && { parts+=("%F{${c_conflict}}✖ ${conflicts}%f"); parts_plain+=("✖ ${conflicts}"); }
  (( changed > 0 )) && { parts+=("%F{${c_changed}}✚ ${changed}%f"); parts_plain+=("✚ ${changed}"); }
  (( untracked > 0 )) && { parts+=("%F{${c_untracked}}… ${untracked}%f"); parts_plain+=("… ${untracked}"); }
  (( stashes > 0 )) && { parts+=("%F{${c_stashed}}⚑ ${stashes}%f"); parts_plain+=("⚑ ${stashes}"); }

  GIT_PROMPT="%F{${c_right_bg}}%f%K{${c_right_bg}}%F{${c_branch}} ${branch}"
  GIT_PROMPT_PLAIN=" ${branch} "

  if (( ${#parts} )); then
    GIT_PROMPT+=" %F{${c_right_fg}}${parts[*]}"
    GIT_PROMPT_PLAIN+="${(j: :)parts_plain} "
  fi

  GIT_PROMPT+=' %f%k'
}

__right_block() {
  local from_bg=$1 bg=$2 fg=$3 text=$4
  print -r -- "%K{${from_bg}}%F{${bg}}%f%k%K{${bg}}%F{${fg}} ${text} %f%k"
}

__build_prompt() {
  local last_status=$1 timer=$2
  local identity right_prompt right_plain left_plain cols pad padding
  local c_path_fg c_path_bg c_right_bg c_prompt_fg c_prompt_bg c_timer_bg c_timer_fg c_exit_bg c_exit_fg

  c_path_fg=$(__color "$COLOR_PATH_FG")
  c_path_bg=$(__color "$COLOR_PATH_BG")
  c_right_bg=$(__color "$COLOR_RIGHT_BG")
  c_prompt_fg=$(__color "$COLOR_PROMPT_FG")
  c_prompt_bg=$(__color "$COLOR_PROMPT_BG")
  c_timer_bg=$(__color "$COLOR_TIMER_BG")
  c_timer_fg=$(__color "$COLOR_TIMER_FG")
  c_exit_bg=$(__color "$COLOR_EXIT_BG")
  c_exit_fg=$(__color "$COLOR_EXIT_FG")

  PWD_PROMPT=$(__short_pwd)
  __git_prompt

  PROMPT_LINE1="%K{${c_path_bg}}%F{${c_path_fg}}${PWD_PROMPT} %f%k%F{${c_path_bg}}%f"

  identity=$(__prompt_identity)
  if [[ -n $identity ]]; then
    PROMPT_LINE2="%K{${c_prompt_bg}}%F{${c_prompt_fg}} ${identity} %f%k%F{${c_prompt_bg}}%f "
  else
    PROMPT_LINE2="%K{${c_prompt_bg}}%F{${c_prompt_fg}} %f%k%F{${c_prompt_bg}}%f "
  fi

  right_prompt=$GIT_PROMPT
  right_plain=$GIT_PROMPT_PLAIN

  if [[ -n $timer && $SHOW_TIMER -ne 0 ]]; then
    right_prompt+="$(__right_block "$c_right_bg" "$c_timer_bg" "$c_timer_fg" "$timer")"
    right_plain+=" ${timer} "
  fi

  if (( last_status != 0 && SHOW_EXITCODE != 0 )); then
    if [[ -n $timer && $SHOW_TIMER -ne 0 ]]; then
      right_prompt+="$(__right_block "$c_timer_bg" "$c_exit_bg" "$c_exit_fg" "$last_status")"
    else
      right_prompt+="$(__right_block "$c_right_bg" "$c_exit_bg" "$c_exit_fg" "$last_status")"
    fi
    right_plain+=" ${last_status} "
  fi

  [[ -n $right_plain ]] || return

  left_plain="${PWD_PROMPT} "
  cols=${COLUMNS:-80}
  (( cols > 0 )) || cols=80
  pad=$(( cols - ${#left_plain} - ${#right_plain} ))
  (( pad < 1 )) && pad=1
  padding=${(l:${pad}:: :)''}
  PROMPT_LINE1+="${padding}${right_prompt}"
}

preexec() {
  __cmd_start=$SECONDS
}

precmd() {
  local last_status=$? elapsed timer

  if (( __empty_accept )); then
    last_status=0
    __empty_accept=0
  fi

  timer=''
  if [[ -n $__cmd_start ]]; then
    elapsed=$(( SECONDS - __cmd_start ))
    (( elapsed > 3 )) && timer=$(__format_elapsed "$elapsed")
  fi

  __last_status=$last_status
  __last_timer=$timer
  __build_prompt "$__last_status" "$__last_timer"
  __cmd_start=''
}

__accept_line() {
  [[ -z ${BUFFER//[[:space:]]/} ]] && __empty_accept=1 || __empty_accept=0
  zle .accept-line
}

TRAPWINCH() {
  __build_prompt "$__last_status" "$__last_timer"
  zle reset-prompt 2>/dev/null || true
}

if [[ -o interactive ]]; then
  zle -N accept-line __accept_line
fi

PROMPT='${PROMPT_LINE1}'$'\n''${PROMPT_LINE2}'
RPROMPT=''
