#!/usr/bin/env zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2020-2026 Jürgen Thelen

setopt errexit nounset pipefail
emulate -L zsh

readonly REPO_ROOT=${0:A:h:h}
source "$REPO_ROOT/zsh-status-prompt.zsh"

: ${SHOW_PROMPTS:=1}

typeset -a TEMP_DIRS=()

cleanup() {
  local dir
  for dir in "${TEMP_DIRS[@]}"; do
    [[ -d $dir ]] && rm -rf -- "$dir"
  done
}

trap cleanup EXIT

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

assert_contains() {
  local haystack=$1 needle=$2 label=$3
  [[ $haystack == *$needle* ]] || fail "$label"
}

assert_not_contains() {
  local haystack=$1 needle=$2 label=$3
  [[ $haystack != *$needle* ]] || fail "$label"
}

assert_eq() {
  local got=$1 expected=$2 label=$3
  [[ $got == $expected ]] || fail "$label"
}

show_prompt() {
  local label=$1 repo=$2
  (( SHOW_PROMPTS )) || return 0
  (
    cd "$repo"
    __build_prompt 0 ''
    print -r -- "$label"
    print -P -- "$PROMPT_LINE1"
    print -P -- "$PROMPT_LINE2"
    print
  )
}

show_text() {
  local label=$1 value=$2 repo=$3
  (( SHOW_PROMPTS )) || return 0
  local c_path_fg c_path_bg
  c_path_fg=$(__color "$COLOR_PATH_FG")
  c_path_bg=$(__color "$COLOR_PATH_BG")
  print -r -- "$label"
  print -P -- "%K{${c_path_bg}}%F{${c_path_fg}} ${value} %f%k%F{${c_path_bg}}%f"
  print -P -- "$(render_prompt_line2 "$repo")"
  print
}

show_rendered_line() {
  local label=$1 line=$2 repo=$3
  (( SHOW_PROMPTS )) || return 0
  print -r -- "$label"
  print -P -- "$line"
  print -P -- "$(render_prompt_line2 "$repo")"
  print
}

show_rendered_line2() {
  local label=$1 line=$2
  (( SHOW_PROMPTS )) || return 0
  print -r -- "$label"
  print -r -- "$line"
  print
}

render_prompt_line2() {
  local repo=$1
  (
    cd "$repo"
    __build_prompt 0 ''
    print -P -- "$PROMPT_LINE2"
  )
}

new_tmpdir() {
  local dir
  dir=$(mktemp -d /tmp/zsh-status-prompt.XXXXXX)
  TEMP_DIRS+=("$dir")
  print -r -- "$dir"
}

init_repo() {
  local repo=$1
  (
    cd "$repo"
    if ! git init -b main >/dev/null 2>&1; then
      git init >/dev/null
      git symbolic-ref HEAD refs/heads/main >/dev/null
    fi
    git config user.name 'Test User'
    git config user.email 'test@example.com'
  )
}

seed_repo() {
  local repo=$1
  local tracked=${2:-tracked.txt}
  (
    cd "$repo"
    print -r -- 'base' > "$tracked"
    git add "$tracked"
    git commit -m 'initial' >/dev/null
  )
}

prompt_plain() {
  local repo=$1
  (
    cd "$repo"
    __git_prompt
    print -r -- "$GIT_PROMPT_PLAIN"
  )
}

test_clean() {
  local repo output
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  output=$(prompt_plain "$repo")
  show_prompt 'clean' "$repo"
  assert_contains "$output" ' main ' 'clean repo should show branch name'
}

test_worktree_counts() {
  local repo output
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  (
    cd "$repo"
    print -r -- 'staged' > staged.txt
    git add staged.txt
    print -r -- 'changed' > tracked.txt
    print -r -- 'untracked' > untracked.txt
  )

  output=$(prompt_plain "$repo")
  show_prompt 'worktree' "$repo"
  assert_contains "$output" '● 1' 'staged count should be shown'
  assert_contains "$output" '✚ 1' 'changed count should be shown'
  assert_contains "$output" '… 1' 'untracked count should be shown'
}

test_conflict_count() {
  local repo output
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  (
    cd "$repo"
    git checkout -b feature >/dev/null 2>&1
    print -r -- 'feature side' > tracked.txt
    git commit -am 'feature change' >/dev/null
    git checkout main >/dev/null 2>&1
    print -r -- 'main side' > tracked.txt
    git commit -am 'main change' >/dev/null
    git merge feature >/dev/null 2>&1 || true
  )

  output=$(prompt_plain "$repo")
  show_prompt 'conflict' "$repo"
  assert_contains "$output" '✖ 1' 'merge conflicts should be shown'
}

test_stash_count() {
  local repo output
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  (
    cd "$repo"
    print -r -- 'stashed change' > tracked.txt
    git stash push -m 'test stash' >/dev/null
  )

  output=$(prompt_plain "$repo")
  show_prompt 'stash' "$repo"
  assert_contains "$output" '⚑ 1' 'stash count should be shown'
}

test_ahead_behind_counts() {
  local origin local_clone peer_clone output
  origin=$(new_tmpdir)
  local_clone=$(new_tmpdir)
  peer_clone=$(new_tmpdir)

  git init --bare "$origin/origin.git" >/dev/null 2>&1
  (
    cd "$origin/origin.git"
    git symbolic-ref HEAD refs/heads/main >/dev/null
  )

  git clone "$origin/origin.git" "$local_clone" >/dev/null 2>&1
  (
    cd "$local_clone"
    git config user.name 'Test User'
    git config user.email 'test@example.com'
    print -r -- 'base' > tracked.txt
    git add tracked.txt
    git commit -m 'initial' >/dev/null
    git push -u origin main >/dev/null 2>&1
  )

  git clone "$origin/origin.git" "$peer_clone" >/dev/null 2>&1
  (
    cd "$local_clone"
    print -r -- 'local ahead' > ahead.txt
    git add ahead.txt
    git commit -m 'local ahead' >/dev/null
    git push >/dev/null 2>&1
  )
  (
    cd "$peer_clone"
    git config user.name 'Test User'
    git config user.email 'test@example.com'
    print -r -- 'peer ahead' > behind.txt
    git add behind.txt
    git commit -m 'peer ahead' >/dev/null
    git fetch origin >/dev/null 2>&1
  )

  output=$(prompt_plain "$peer_clone")
  show_prompt 'ahead-behind' "$peer_clone"
  assert_contains "$output" '↓ 1' 'behind count should be shown'
  assert_contains "$output" '↑ 1' 'ahead count should be shown'
}

test_detached_head() {
  local repo output
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  (
    cd "$repo"
    git checkout --detach HEAD >/dev/null 2>&1
  )

  output=$(prompt_plain "$repo")
  show_prompt 'detached' "$repo"
  assert_contains "$output" 'HEAD@' 'detached HEAD should be shown'
}

test_detached_head_with_counts() {
  local repo prompt
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  (
    cd "$repo"
    git checkout --detach HEAD >/dev/null 2>&1
    print -r -- 'dirty' > tracked.txt
    git add tracked.txt
    print -r -- 'more dirty' > tracked.txt
  )

  prompt=$(cd "$repo" && __git_prompt && print -r -- "$GIT_PROMPT")
  show_prompt 'detached with counts' "$repo"
  assert_contains "$prompt" '%F{98} HEAD@' 'detached HEAD should keep detached color with counts'
}

test_short_pwd() {
  local repo output expected
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  output=$(cd "$repo" && __short_pwd)
  show_text 'shallow path' "$output" "$repo"

  expected="${repo/#$HOME/~}"
  expected="${expected//\//  }"
  assert_eq "$output" "$expected" 'short paths should show the full path'
}

test_deep_pwd() {
  local repo deep output expected parts
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  deep="$repo/a/b/c/d/e/f"
  mkdir -p "$deep"

  output=$(cd "$deep" && __short_pwd)
  show_text 'deep path' "$output" "$repo"

  parts=(${(@s:/:)deep})
  expected="...  ${(j:  :)parts[-5,-1]}"
  assert_eq "$output" "$expected" 'deep paths should show the last five folders'
}

test_timer_block() {
  local repo timer prompt
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  timer=$(cd "$repo" && __cmd_start=$((SECONDS - 4)) precmd && print -r -- "$__last_timer")
  prompt=$(cd "$repo" && __cmd_start=$((SECONDS - 4)) precmd && print -r -- "$PROMPT_LINE1")

  show_rendered_line 'timer' "$prompt" "$repo"
  assert_eq "$timer" '00:00:04' 'timer should format elapsed time over 3 seconds'
  assert_contains "$prompt" '00:00:04' 'timer block should be shown in the prompt'
}

test_timer_toggle() {
  local repo prompt
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  prompt=$(cd "$repo" && SHOW_TIMER=0 __build_prompt 0 '00:00:04' && print -r -- "$PROMPT_LINE1")

  show_rendered_line 'timer hidden' "$prompt" "$repo"
  assert_not_contains "$prompt" '00:00:04' 'timer block should be hidden when disabled'
}

test_exit_code_block() {
  local repo prompt disabled
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  prompt=$(cd "$repo" && __build_prompt 130 '' && print -r -- "$PROMPT_LINE1")

  show_rendered_line 'exit code' "$prompt" "$repo"
  assert_contains "$prompt" '130' 'exit code block should be shown in the prompt'

  disabled=$(cd "$repo" && SHOW_EXITCODE=0 __build_prompt 130 '' && print -r -- "$PROMPT_LINE1")
  show_rendered_line 'exit code hidden' "$disabled" "$repo"
  assert_not_contains "$disabled" '130' 'exit code block should be hidden when disabled'
}

test_timer_and_exit_blocks() {
  local repo prompt disabled
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  prompt=$(cd "$repo" && __build_prompt 130 '00:00:04' && print -r -- "$PROMPT_LINE1")

  show_rendered_line 'timer + exit code' "$prompt" "$repo"
  assert_contains "$prompt" '00:00:04' 'timer block should be shown with exit code'
  assert_contains "$prompt" '130' 'exit code block should be shown with timer'

  disabled=$(cd "$repo" && SHOW_EXITCODE=0 __build_prompt 130 '00:00:04' && print -r -- "$PROMPT_LINE1")
  show_rendered_line 'timer only' "$disabled" "$repo"
  assert_contains "$disabled" '00:00:04' 'timer block should remain with exit code disabled'
  assert_not_contains "$disabled" '130' 'exit code block should be hidden when disabled'
}

test_hostname_toggle() {
  local repo line_default line_enabled line_host_only expected_host expected_user
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  line_default=$(render_prompt_line2 "$repo")
  expected_host=${HOST%%.*}
  [[ -n $expected_host ]] || expected_host=$(hostname -s)
  expected_user=${USER:-$(whoami)}
  show_rendered_line2 'hostname default' "$line_default"
  assert_not_contains "$line_default" "${expected_user}@$expected_host" 'hostname should be hidden by default'
  assert_contains "$line_default" "${expected_user}" 'username should be shown by default'

  line_enabled=$(
    SHOW_HOSTNAME=1
    render_prompt_line2 "$repo"
  )
  show_rendered_line2 'hostname enabled' "$line_enabled"
  assert_contains "$line_enabled" "${expected_user}@$expected_host" 'hostname should be shown when enabled'

  line_host_only=$(
    SHOW_HOSTNAME=1 SHOW_USERNAME=0
    render_prompt_line2 "$repo"
  )
  show_rendered_line2 'hostname only' "$line_host_only"
  assert_not_contains "$line_host_only" "$expected_user" 'username should be hidden when disabled'
  assert_contains "$line_host_only" "$expected_host" 'hostname should remain when username is disabled'
  assert_not_contains "$line_host_only" "@$expected_host" 'host-only prompt should not include obsolete @ prefix'
}

test_privilege_char_toggle() {
  local repo line_default line_enabled expected_user expected_priv
  repo=$(new_tmpdir)
  init_repo "$repo"
  seed_repo "$repo"

  expected_user=${USER:-$(whoami)}
  [[ ${EUID:-$(id -u)} -eq 0 ]] && expected_priv='#' || expected_priv='%'

  line_default=$(render_prompt_line2 "$repo")
  show_rendered_line2 'privilege default' "$line_default"
  assert_not_contains "$line_default" "$expected_priv" 'privilege char should be hidden by default'

  line_enabled=$(
    SHOW_PRIVILEGE_CHAR=1
    render_prompt_line2 "$repo"
  )
  show_rendered_line2 'privilege enabled' "$line_enabled"
  assert_contains "$line_enabled" "${expected_user} ${expected_priv}" 'privilege char should be shown when enabled'
}

main() {
  test_short_pwd
  test_deep_pwd
  test_clean
  test_worktree_counts
  test_conflict_count
  test_stash_count
  test_ahead_behind_counts
  test_detached_head
  test_detached_head_with_counts
  test_timer_block
  test_timer_toggle
  test_exit_code_block
  test_timer_and_exit_blocks
  test_hostname_toggle
  test_privilege_char_toggle
  print -r -- 'ok'
}

main "$@"
