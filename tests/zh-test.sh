#!/bin/bash
# zh send: empty-batch rows of the ctrl-space truth table, target selection, delivery.
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

FOCUS='herdr-app do agent.focus --terminal'

echo "row 1: no selection focuses the repo's agent and raises the window"
setup_case row1
set_agents "$(agent t3 "$REPO" idle)" "$(agent t4 /elsewhere idle)"
run_send "$REPO" "$REPO/src/a.txt" 2
out=$(log)
assert_contains "$out" "$FOCUS t3" "focus t3"
assert_not_contains "$out" "$FOCUS t4" "other repo untouched"
assert_contains "$out" "hyprctl dispatch hl.dsp.focus({ window = \"class:herdr-app\" })" "window raised"
assert_not_contains "$out" "hc send" "no send"
assert_not_contains "$out" "hc keys" "no Enter"
assert_not_contains "$out" "terminal.paste" "no paste"

echo "row 2: selection pastes @path#L plus selection, no Enter, then focuses"
setup_case row2
set_agents "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=$'two\nthree' run_send "$REPO" "$REPO/src/a.txt" 2
out=$(log)
assert_contains "$out" "$FOCUS t3" "focus"
assert_contains "$out" "do terminal.paste" "pasted"
assert_not_contains "$out" "hc send" "one-off paste never submits"
assert_not_contains "$out" "hc keys" "never presses keys (no Enter)"
assert_eq $'@src/a.txt#L2-3\n```\ntwo\nthree\n```' "$(pasted)" "paste text"
# focus must precede paste so the paste lands in the agent
f=$(grep -n 'agent.focus' "$STUB_LOG" | head -1 | cut -d: -f1); p=$(grep -n 'terminal.paste' "$STUB_LOG" | head -1 | cut -d: -f1)
if ((f < p)); then pass; else fail "focus must precede paste"; fi

echo "row 2: single line uses #Lx; clipboard is restored"
setup_case oneline
set_agents "$(agent t3 "$REPO" idle)"
printf 'precious' > "$STUB_DIR/clipboard"
ZED_SELECTED_TEXT='three' run_send "$REPO" "$REPO/src/a.txt" 3
assert_contains "$(pasted)" "@src/a.txt#L3"$'\n' "single-line ref"
assert_not_contains "$(pasted)" "#L3-" "no range"
assert_eq "precious" "$(cat "$STUB_DIR/clipboard")" "clipboard restored"

echo "row 2: ZED_ROW at the selection end still finds the start"
setup_case rowend
set_agents "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=$'two\nthree' run_send "$REPO" "$REPO/src/a.txt" 3
assert_contains "$(pasted)" "@src/a.txt#L2-3" "range from end row"

echo "focused agent preferred when in the repo"
setup_case focused
set_agents "$(agent t3 "$REPO" idle)" "$(agent t4 "$REPO" blocked)" "$(agent t5 "$REPO" done)"
set_focused t3
run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "focused t3 wins"
assert_not_contains "$out" "$FOCUS t4" "not blocked t4"

echo "focused agent in another repo is ignored"
setup_case focused-else
set_agents "$(agent t3 "$REPO" idle)" "$(agent t9 /elsewhere working)"
set_focused t9
run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "t3"
assert_not_contains "$out" "$FOCUS t9" "t9 other repo"

echo "ranking fallback: blocked > done > working > idle"
setup_case rank
set_agents "$(agent t1 "$REPO" idle)" "$(agent t2 "$REPO" working)" "$(agent t3 "$REPO" done)"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_contains "$(log)" "$FOCUS t3" "done beats working/idle"
setup_case rank2
set_agents "$(agent t1 "$REPO" idle)" "$(agent t2 "$REPO" working)"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_contains "$(log)" "$FOCUS t2" "working beats idle"
setup_case rank3
set_agents "$(agent t1 "$REPO" done)" "$(agent t2 "$REPO" blocked)"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_contains "$(log)" "$FOCUS t2" "blocked beats done"

echo "remote and non-agent terminals are ignored"
setup_case remote
set_agents \
  '{"address":"omaserve/t7","agent":"claude-code","cwd":"'"$REPO"'","state":"live","status":"blocked"}' \
  '{"address":"t8","agent":"claude-code","machine":"omaserve","cwd":"'"$REPO"'","state":"live","status":"blocked"}' \
  '{"address":"t6","agent":"bash","cwd":"'"$REPO"'","state":"live"}' \
  '{"address":"t10","agent":"claude-code","cwd":"'"$REPO"'","state":"finished","status":"idle"}' \
  "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=x run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "only local agent"
for t in omaserve/t7 t8 t6 t10; do assert_not_contains "$out" "$FOCUS $t" "ignored $t"; done

echo "worktrees map to their own git root"
setup_case worktree
set_agents "$(agent t3 "$REPO" idle)" "$(agent t4 "$WT" idle)" "$(agent t5 "$WT/sub" working)"
mkdir -p "$WT/sub"
run_send "$WT" "$WT/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t5" "worktree agent (subdir cwd) ranked working > idle"
assert_not_contains "$out" "$FOCUS t3" "main checkout agent not used"
setup_case worktree2
set_agents "$(agent t3 "$REPO" idle)" "$(agent t4 "$WT" idle)"
run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "main checkout"
assert_not_contains "$out" "$FOCUS t4" "worktree agent not used for main"
setup_case subdir
set_agents "$(agent t3 "$REPO" idle)"
run_send "$REPO/src" "$REPO/src/a.txt" 1
assert_contains "$(log)" "$FOCUS t3" "Zed root may be a subdir"

echo "blocked agent: no paste, still focuses, notifies"
setup_case blocked
set_agents "$(agent t3 "$REPO" blocked)"
ZED_SELECTED_TEXT=x run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "focused"
assert_contains "$out" "notify-send" "notified"
assert_not_contains "$out" "terminal.paste" "no paste"
assert_not_contains "$out" "hc send" "no send"
assert_eq "" "$(pasted)" "nothing pasted"

echo "no agent: notification, no focus"
setup_case none
set_agents "$(agent t4 /elsewhere idle)"
ZED_SELECTED_TEXT=x run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "notify-send" "notified"
assert_not_contains "$out" "agent.focus" "no focus"
assert_not_contains "$out" "terminal.paste" "no paste"

echo "add: selection + note queues an item and notifies the count"
setup_case add1
set_agents "$(agent t3 "$REPO" idle)"
set_note "rename this"
ZED_SELECTED_TEXT=$'two\nthree' run_add "$REPO" "$REPO/src/a.txt" 2
assert_eq '[{"path":"src/a.txt","lines":"L2-3","selection":"two\nthree","note":"rename this"}]' "$(batch_json | jq -c .)" "item stored"
assert_contains "$(log)" "omarchy-menu-input" "prompted"
assert_contains "$(log)" "notify-send zh 1 comment" "count notified"
assert_not_contains "$(log)" "terminal.paste" "add never sends"

echo "add: Esc adds without a note; no selection uses the cursor line"
setup_case add2
run_add "$REPO" "$REPO/src/a.txt" 3
assert_eq '[{"path":"src/a.txt","lines":"L3","selection":"three","note":""}]' "$(batch_json | jq -c .)" "cursor line, no note"
set_note "again"
run_add "$REPO" "$REPO/src/a.txt" 4
assert_eq 2 "$(batch_json | jq length)" "appended"
assert_contains "$(log)" "notify-send zh 2 comments" "plural count"

echo "add: batches are per git root"
setup_case addroot
run_add "$REPO" "$REPO/src/a.txt" 1
run_add "$WT" "$WT/src/a.txt" 1
assert_eq 2 "$(ls "$XDG_STATE_HOME"/zerdr/batch/*.json | wc -l)" "one file per root"

echo "clear: discards the batch"
setup_case clear
run_add "$REPO" "$REPO/src/a.txt" 1
run_clear "$REPO"
assert_eq '[]' "$(batch_json | jq -c .)" "cleared"

echo "row 3: batch + no selection submits, presses Enter once, clears, focuses"
setup_case sub3
set_agents "$(agent t3 "$REPO" idle)"
set_note "first"
ZED_SELECTED_TEXT=$'two\nthree' run_add "$REPO" "$REPO/src/a.txt" 2
set_note "second"
ZED_SELECTED_TEXT=four run_add "$REPO" "$REPO/src/a.txt" 4
: > "$STUB_LOG"
run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_eq $'Review comments:\n\n1. @src/a.txt#L2-3\n```\ntwo\nthree\n```\nfirst\n\n2. @src/a.txt#L4\n```\nfour\n```\nsecond' "$(sent)" "message"
assert_eq 1 "$(grep -c '^hc send t3 ' <<<"$out")" "submitted once by id"
assert_not_contains "$out" "--force" "never forced"
assert_not_contains "$out" "terminal.paste" "no clipboard paste"
assert_contains "$out" "$FOCUS t3" "focused"
assert_eq '[]' "$(batch_json | jq -c .)" "batch cleared"
: > "$STUB_LOG"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_not_contains "$(log)" "hc send" "no double send"

echo "row 4: batch + selection prompts for a note, appends, submits all"
setup_case sub4
set_agents "$(agent t3 "$REPO" idle)"
run_add "$REPO" "$REPO/src/a.txt" 1
set_note "now this"
: > "$STUB_LOG"
ZED_SELECTED_TEXT=three run_send "$REPO" "$REPO/src/a.txt" 3
assert_contains "$(log)" "omarchy-menu-input" "prompted"
assert_contains "$(sent)" "1. @src/a.txt#L1"$'\n```\none\n```\n\n2. @src/a.txt#L3'$'\n```\nthree\n```\nnow this' "both items"
assert_eq 1 "$(grep -c '^hc send' "$STUB_LOG")" "submitted once"
assert_eq '[]' "$(batch_json | jq -c .)" "cleared"
echo "row 4: Esc on the note still appends and submits"
setup_case sub4b
set_agents "$(agent t3 "$REPO" idle)"
run_add "$REPO" "$REPO/src/a.txt" 1
ZED_SELECTED_TEXT=three run_send "$REPO" "$REPO/src/a.txt" 3
assert_contains "$(sent)" "2. @src/a.txt#L3"$'\n```\nthree\n```' "appended without note"
assert_eq '[]' "$(batch_json | jq -c .)" "cleared"

echo "message: long selections are trimmed to 20 lines"
setup_case sub-trim
set_agents "$(agent t3 "$REPO" idle)"
seq 1 30 > "$REPO/src/long.txt"
ZED_SELECTED_TEXT="$(seq 1 30)" run_add "$REPO" "$REPO/src/long.txt" 1
run_send "$REPO" "$REPO/src/long.txt" 1
assert_contains "$(sent)" "@src/long.txt#L1-30" "full range in header"
assert_contains "$(sent)" $'\n20\n...\n```' "trimmed with marker"
assert_not_contains "$(sent)" $'\n21\n' "line 21 dropped"

echo "blocked agent: batch kept, nothing sent, focused, notified"
setup_case blockedbatch
set_agents "$(agent t3 "$REPO" blocked)"
run_add "$REPO" "$REPO/src/a.txt" 1
: > "$STUB_LOG"
ZED_SELECTED_TEXT=three run_send "$REPO" "$REPO/src/a.txt" 3
out=$(log)
assert_eq 1 "$(batch_json | jq length)" "batch kept, selection not appended"
assert_contains "$out" "$FOCUS t3" "focused"
assert_contains "$out" "notify-send" "notified"
assert_not_contains "$out" "terminal.paste" "no paste"
assert_not_contains "$out" "hc send" "no submit"
assert_not_contains "$out" "omarchy-menu-input" "no prompt"

echo "working agent: batch delivered"
setup_case sub-working
set_agents "$(agent t3 "$REPO" working)"
run_add "$REPO" "$REPO/src/a.txt" 1
run_send "$REPO" "$REPO/src/a.txt" 1
assert_contains "$(sent)" "Review comments:" "delivered"
assert_eq '[]' "$(batch_json | jq -c .)" "cleared"

echo "no agent: batch kept"
setup_case sub-noagent
run_add "$REPO" "$REPO/src/a.txt" 1
run_send "$REPO" "$REPO/src/a.txt" 1
assert_eq 1 "$(batch_json | jq length)" "kept"

echo "one-off and focus-only cases never submit"
for l in "$TMP"/*/stub/log; do
  case $(basename "$(dirname "$(dirname "$l")")") in sub*|conc*|fail*) continue ;; esac
  assert_not_contains "$(cat "$l")" "hc send" "no hc send ($l)"
  assert_not_contains "$(cat "$l")" "hc keys" "no Enter ($l)"
done

echo "agent cwd: foreground.cwd decides, not the launch cwd"
setup_case fg
set_agents "$(agent t3 "$HOME" idle)" "$(agent t4 "$REPO" idle)"
set_fg t3 "$REPO/src"
set_fg t4 /elsewhere
run_send "$REPO" "$REPO/src/a.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t3" "launched in ~, cd'd into the repo"
assert_not_contains "$out" "$FOCUS t4" "launched in repo, left it"

echo "nested worktree: a file inside it maps to that worktree, not the opened repo"
setup_case nested
git -C "$REPO" worktree add -q "$REPO/nested" -b nested 2>/dev/null
mkdir -p "$REPO/nested/src"; echo x > "$REPO/nested/src/b.txt"
set_agents "$(agent t3 "$REPO" idle)" "$(agent t4 "$REPO/nested" idle)"
run_send "$REPO" "$REPO/nested/src/b.txt" 1
out=$(log)
assert_contains "$out" "$FOCUS t4" "nested worktree agent"
assert_not_contains "$out" "$FOCUS t3" "outer repo agent"

echo "no active editor: root from env, selection ignored, add refuses"
setup_case nofile
set_agents "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=stale run_send "$REPO" "" ""
out=$(log)
assert_contains "$out" "$FOCUS t3" "focused"
assert_not_contains "$out" "terminal.paste" "no paste"
run_add "$REPO" "" ""
assert_eq '[]' "$(batch_json | jq -c .)" "nothing queued"
assert_contains "$(log)" "notify-send" "notified"
run_add "$REPO" "$REPO/src/a.txt" 1
: > "$STUB_LOG"
ZED_SELECTED_TEXT=stale run_send "$REPO" "" ""
assert_contains "$(sent)" "Review comments:" "batch submitted; stale selection not appended"
assert_eq 1 "$(grep -c '^hc send' "$STUB_LOG")" "submitted"

echo "symlinked file path still yields a relative mention"
setup_case symlink
set_agents "$(agent t3 "$REPO" idle)"
ln -s "$REPO" "$TMP/symlink/link"
ZED_SELECTED_TEXT=two run_send "$REPO" "$TMP/symlink/link/src/a.txt" 2
assert_contains "$(pasted)" "@src/a.txt#L2" "relative"

echo "failures: paste fails -> one-off not delivered; focus fails -> no paste, notified"
setup_case failfocus1
set_agents "$(agent t3 "$REPO" idle)"
touch "$STUB_DIR/fail_focus"
ZED_SELECTED_TEXT=two run_send "$REPO" "$REPO/src/a.txt" 2
assert_not_contains "$(log)" "terminal.paste" "no paste when focus fails"
assert_contains "$(log)" "notify-send" "notified"

setup_case failpaste
set_agents "$(agent t3 "$REPO" idle)"
touch "$STUB_DIR/fail_paste"
ZED_SELECTED_TEXT=two run_send "$REPO" "$REPO/src/a.txt" 2
assert_contains "$(log)" "notify-send" "notified on paste failure"
assert_not_contains "$(log)" "hc send" "never submits"

echo "failures: hc send fails -> batch kept, no Enter"
setup_case failsend
set_agents "$(agent t3 "$REPO" idle)"
run_add "$REPO" "$REPO/src/a.txt" 1
touch "$STUB_DIR/fail_send"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_eq 1 "$(batch_json | jq length)" "batch kept"
assert_not_contains "$(log)" "hc keys" "no Enter"
assert_contains "$(log)" "notify-send" "notified"

echo "failures: focus fails on batch submit -> batch kept, nothing sent"
setup_case failfocus2
set_agents "$(agent t3 "$REPO" idle)"
run_add "$REPO" "$REPO/src/a.txt" 1
touch "$STUB_DIR/fail_focus"
run_send "$REPO" "$REPO/src/a.txt" 1
assert_eq 1 "$(batch_json | jq length)" "batch kept"
assert_not_contains "$(log)" "hc send" "nothing sent"
assert_not_contains "$(log)" "hc keys" "no Enter"

echo "clipboard: non-empty restored with its type; empty clipboard is cleared afterwards"
setup_case clip
set_agents "$(agent t3 "$REPO" idle)"
printf 'precious' > "$STUB_DIR/clipboard"
ZED_SELECTED_TEXT=two run_send "$REPO" "$REPO/src/a.txt" 2
assert_contains "$(log)" "wl-copy -t text/plain" "restored with MIME type"
assert_eq precious "$(cat "$STUB_DIR/clipboard")" "restored"
setup_case clipempty
set_agents "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=two run_send "$REPO" "$REPO/src/a.txt" 2
assert_contains "$(pasted)" "@src/a.txt#L2" "pasted"
assert_contains "$(log)" "wl-copy --clear" "cleared"
assert_eq "" "$(cat "$STUB_DIR/clipboard" 2>/dev/null)" "clipboard empty"

echo "concurrency: simultaneous adds both land"
setup_case conc
for i in 1 2 3 4 5 6; do run_add "$REPO" "$REPO/src/a.txt" $((i % 4 + 1)) & done
wait
assert_eq 6 "$(batch_json | jq length)" "all adds kept"

finish
