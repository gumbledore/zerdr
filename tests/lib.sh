#!/bin/bash
# Shared fixtures. Sourced by each *-test.sh. Stubs shadow the real hc/herdr-app/
# notify-send/hyprctl/wl-copy; HOME and XDG_STATE_HOME are throwaway.
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

export PATH="$ROOT/tests/stubs:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

PASS=0 FAIL=0
TEST_NAME=${TEST_NAME:-$(basename -- "$0" .sh)}

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $*" >&2; }
assert_eq() { if [[ $1 == "$2" ]]; then pass; else fail "$3: expected [$1] got [$2]"; fi }
assert_contains() { if [[ $1 == *"$2"* ]]; then pass; else fail "$3: [$2] not found in: $1"; fi }
assert_not_contains() { if [[ $1 != *"$2"* ]]; then pass; else fail "$3: [$2] unexpectedly present in: $1"; fi }
finish() { echo "$TEST_NAME: $PASS passed, $FAIL failed"; [[ $FAIL -eq 0 ]]; }

# setup_case <name>: exports HOME, XDG_STATE_HOME, STUB_DIR, STUB_LOG, REPO (a git
# repo with src/a.txt) and WT (a worktree of it), with no agents and none focused.
setup_case() {
  local d="$TMP/$1"
  export HOME="$d/home" XDG_STATE_HOME="$d/state" STUB_DIR="$d/stub" STUB_LOG="$d/stub/log"
  export REPO="$d/repo" WT="$d/repo-wt"
  mkdir -p "$HOME" "$STUB_DIR" "$REPO/src"
  : > "$STUB_LOG"
  printf 'one\ntwo\nthree\nfour\n' > "$REPO/src/a.txt"
  git init -q "$REPO" && git -C "$REPO" add -A && git -C "$REPO" commit -qm init
  git -C "$REPO" worktree add -q "$WT" -b wt
  unset ZED_SELECTED_TEXT
  set_agents
  set_focused ''
}

# set_agents <terminal-json>...: what `hc ls --json` returns.
set_agents() { local IFS=,; printf '{"machines":[],"terminals":[%s]}\n' "$*" > "$STUB_DIR/ls.json"; }
# set_focused <terminal>: `herdr-app status` .agent.
set_focused() { printf '{"agent":"%s"}\n' "$1" > "$STUB_DIR/status.json"; }
# agent <addr> <cwd> <status>: one local agent terminal.
agent() { printf '{"address":"%s","agent":"claude-code","cwd":"%s","state":"live","status":"%s"}' "$1" "$2" "$3"; }

# run_send <root> <file> <row>: invoke bin/zh as the Zed task does (selection in env).
run_send() { "$ROOT/bin/zh" send "$@" >/dev/null 2>&1; }
log() { cat "$STUB_LOG"; }
pasted() { cat "$STUB_DIR/pasted" 2>/dev/null; }

# run_add / run_clear: invoke bin/zh as the Zed tasks do.
run_add() { "$ROOT/bin/zh" add "$@" >/dev/null 2>&1; }
run_clear() { "$ROOT/bin/zh" clear "$@" >/dev/null 2>&1; }
# set_note <text>: what the note prompt returns (never called = Esc).
set_note() { printf '%s\n' "$1" > "$STUB_DIR/note"; }
# batch_json <root>: the batch file contents ([] when none).
batch_json() { cat "$XDG_STATE_HOME"/zerdr/batch/*.json 2>/dev/null || echo '[]'; }
