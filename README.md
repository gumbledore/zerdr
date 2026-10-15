# zerdr

Run agents in herdr (in a real terminal), review their work in Zed as it lands, and have
each agent's worktree map to the right Zed window automatically.

## Pieces

| Piece | What it does |
|---|---|
| `herdr-plugin.toml` | herdr plugin `kmg.zed`: adds the actions below and the agent-done notification. |
| `bin/zh` | Shared glue CLI used by the plugin and by Zed tasks. |
| `zed/tasks.json`, `zed/keymap.json` | Zed → herdr: jump to the project's agent, or send it an `@file#Lx-y` reference. |

## How matching works

Everything keys off the **git toplevel** (`git rev-parse --show-toplevel`), which is
worktree-aware:

- **herdr pane → Zed window**: the focused pane's cwd goes to its toplevel, then `zeditor <root>`.
- **Zed window → herdr agent**: `$ZED_WORKTREE_ROOT` goes to agents whose cwd has that same
  toplevel. Ties go blocked > done > working > idle. Worktrees nested inside the main
  checkout stay separate.

## Use

| Where | Action | Effect |
|---|---|---|
| herdr | `kmg.zed.open` | open/focus the pane's project in Zed |
| herdr | `kmg.zed.review` | the agent's net work: one editable diff tab per changed file, vs the branch's fork point from main (committed + uncommitted), or vs HEAD when on main |
| herdr | `kmg.zed.commits` | each commit since the fork point (last 10) in Zed's native commit view |
| herdr (automatic) | agent finishes | notification "Agent done: <project>, N files, M commits". Click it to run `review`; the *Commits* button (if your daemon shows buttons) runs `commits` |
| Zed | `ctrl-alt-h` | focus the project's herdr agent and raise the terminal |
| Zed | `ctrl-alt-l` | type `@file#Lx-y` (current selection) into that agent's prompt, then focus it |

## Install

```sh
./install.sh   # links the plugin, writes Zed tasks/keymap if absent
```

Then add the herdr keybindings that `install.sh` prints.

Config (env): `ZED_BIN` (default `zeditor`), `ZH_TERMINAL_CLASS` (Hyprland class to raise;
default `com.mitchellh.ghostty`), `ZH_MAX_COMMITS` (default 10).

## Known limits (prototype)

- Zed's directory `--diff` mode was unreliable, so `review` opens one tab per file.
  For staging hunks, use Zed's own `git: diff` panel once the window is up.
- herdr marks an agent `done` whenever it stops unwatched, which happens every turn. The notification
  only fires when the agent's work changed since the last one, so turns that only chat stay quiet.
- Zed's own `git: branch diff` (same base, with staging) can't be triggered from outside;
  run it from the command palette once `review` has brought the window up.
- Zed passes task args through a shell without quoting, so paths with spaces break the Zed tasks.
