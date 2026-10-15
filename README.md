# zed-herdr

Run agents in herdr (in a real terminal), review and edit in Zed, and have each
agent's worktree map to the right Zed window automatically.

## Pieces

| Piece | What it does |
|---|---|
| `bridge/claude_zed_bridge.py` | Speaks Claude Code's IDE protocol (the one the VS Code/JetBrains extensions use). Claude sees an IDE called **Zed**; proposed edits open as Zed side-by-side diffs. |
| `herdr-plugin.toml` | herdr plugin `kmg.zed`: starts the bridge on server start, and adds the actions below. |
| `bin/zh` | Shared glue CLI used by the plugin and by Zed tasks. |
| `zed/tasks.json`, `zed/keymap.json` | Zed → herdr: jump to the project's agent, or send it an `@file#Lx-y` reference. |

## How matching works

Everything keys off the **git toplevel** (`git rev-parse --show-toplevel`), which is
worktree-aware:

- **Claude diff → Zed window**: the file's toplevel is the cwd for `zeditor -w --diff`,
  and Zed puts it in the window that owns that project. One bridge serves every Claude
  session, since routing goes by file path, not by session.
- **herdr pane → Zed window**: the focused pane's cwd goes to its toplevel, then `zeditor <root>`.
- **Zed window → herdr agent**: `$ZED_WORKTREE_ROOT` goes to agents whose cwd has that same
  toplevel. Ties go blocked > done > working > idle. Worktrees nested inside the main
  checkout stay separate.

## Use

| Where | Action | Effect |
|---|---|---|
| Claude (any herdr pane) | edit needs permission | diff opens in that project's Zed window. **Save** (ctrl-s) in Zed accepts, including any edits you made on the right side. **Close the tab** to reject. Or answer in the terminal as usual. |
| herdr | `kmg.zed.open` | open/focus the pane's project in Zed |
| herdr | `kmg.zed.review` | the agent's net work: one editable diff tab per changed file, vs the branch's fork point from main (committed + uncommitted), or vs HEAD when on main |
| herdr | `kmg.zed.commits` | each commit since the fork point (last 10) in Zed's native commit view |
| herdr (automatic) | agent finishes | notification "Agent done: <project>, N files, M commits". Click it to run `review`; the *Commits* button (if your daemon shows buttons) runs `commits` |
| herdr | `kmg.zed.bridge` | restart the bridge (live Claude sessions reconnect on their own) |
| Zed | `ctrl-alt-h` | focus the project's herdr agent and raise the terminal |
| Zed | `ctrl-alt-l` | type `@file#Lx-y` (current selection) into that agent's prompt, then focus it |

## Install

```sh
./install.sh   # links the plugin, starts the bridge, writes Zed tasks/keymap if absent
```

Then:
- Add the herdr keybindings that `install.sh` prints.
- Make Claude connect without `/ide`: run `claude --ide`, or turn on `/config` → *Auto-connect to IDE*.
- Diffs show only when Claude asks for permission. In auto / accept-edits mode, edits apply with no prompt.

Config (env): `CLAUDE_ZED_FOLDERS` (colon list the lockfile advertises; default `$HOME`),
`ZED_BIN` (default `zeditor`), `ZH_TERMINAL_CLASS` (Hyprland class to raise; default ghostty).
Logs: `~/.local/state/zed-herdr/bridge.log`.

## Known limits (prototype)

- Zed has no API to close tabs, so diff tabs stay open after you answer in the
  terminal. They go stale but stay harmless (once accepted, the left side matches the right).
- Opening a diff focuses Zed, so each permission prompt pulls focus.
- Zed's directory `--diff` mode was unreliable, so `review` opens one tab per file.
  For staging hunks, use Zed's own `git: diff` panel once the window is up.
- Only diff and open-file tools are offered. Zed exposes no editor state (selection,
  diagnostics) to outside processes, so use `ctrl-alt-l` to send a selection instead.
- The bridge saves exactly what's in the buffer. If you have format-on-save turned on,
  the formatted text is what Claude gets.
- herdr marks an agent `done` whenever it stops unwatched, which happens every turn. The notification
  only fires when the agent's work changed since the last one, so turns that only chat stay quiet.
- Zed's own `git: branch diff` (same base, with staging) can't be triggered from outside;
  run it from the command palette once `review` has brought the window up.
- Zed passes task args through a shell without quoting, so paths with spaces break the Zed tasks.
