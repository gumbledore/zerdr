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
assert_not_contains "$out" "terminal.paste" "no paste"

echo "row 2: selection pastes @path#L plus selection, no Enter, then focuses"
setup_case row2
set_agents "$(agent t3 "$REPO" idle)"
ZED_SELECTED_TEXT=$'two\nthree' run_send "$REPO" "$REPO/src/a.txt" 2
out=$(log)
assert_contains "$out" "$FOCUS t3" "focus"
assert_contains "$out" "do terminal.paste" "pasted"
assert_not_contains "$out" "hc send" "never hc send (it presses Enter)"
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

echo "never presses Enter or hc send, in any scenario"
assert_not_contains "$(cat "$TMP"/*/stub/log)" "hc send" "global: no hc send"
assert_not_contains "$(cat "$TMP"/*/stub/log)" "hc keys" "global: no hc keys"

finish
