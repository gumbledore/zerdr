# zerdr

Drive herdr-app agents from Zed: jump to the repo's agent, or paste a selection into it.

## Pieces

| Piece | What it does |
|---|---|
| `bin/zh` | Glue CLI called by the Zed tasks. Backend is herdr-app / `hc` only. |
| `herdr-app/zerdr/` | herdr-app mod `zerdr` (linked into `~/.config/herdr-app/mods/` by `install.sh`): `zerdr.open` opens the pane's git root in Zed, `zerdr.review` shows the Changes panel. It must sit in a layout block. |
| `zed/tasks.json`, `zed/keymap.json` | Zed tasks "herdr: focus/send", "herdr: add to batch", "herdr: clear batch" and their keys. |
| `tests/` | Stub-PATH tests: `bash tests/run.sh`. |

The old herdr TUI plugin (`open`/`review`/`commits`/`done`, `herdr-plugin.toml`) is gone; see git history.

## Use

| Where | Key | Effect |
|---|---|---|
| Zed | `ctrl-space` | `zh send`: nothing selected, focus the repo's agent and raise the herdr-app window |
| Zed (editor) | `ctrl-space` with a selection | paste `@path#Lx-y` + the selection into the agent's input (no Enter), then focus it |
| Zed (editor) | `ctrl-shift-space` | `zh add` (batch; not implemented yet) |

Pasted format (the code fence keeps multi-line selections intact):

````
@src/a.txt#L2-3
```
two
three
```
````

**Target agent**: local, live, status-reporting terminals from `hc ls --json` whose cwd's git
root equals the Zed root (worktrees are their own root). The agent last focused in herdr-app
wins if it is in that set, else blocked > done > working > idle. Remote agents are never targeted.
A blocked agent gets no paste: it is focused and a notification says so. No agent: notification.

**Paste without Enter**: `hc send` always presses Enter and `hc keys` cannot type arbitrary text,
so `zh` copies the text with `wl-copy`, focuses the agent, runs `herdr-app do terminal.paste`
and restores the clipboard.

State: `~/.local/state/zerdr/batch/<sha1 of git root>.json` (batch items, used from `add`/batch submit).

## Install

```sh
./install.sh   # writes Zed tasks/keymap if absent, links the herdr-app mod
```

Then add the herdr-app keys it prints and put the mod in a layout, e.g. a 1px block
`{"type":"block","size":{"px":1},"content":{"mod":"zerdr"}}`.

Config (env): `ZH_TERMINAL_CLASS` (Hyprland class to raise; default `herdr-app`).
Needs `hc`, `herdr-app`, `jq`, `wl-clipboard`, `hyprctl`, `notify-send`.

## Known limits

- Zed passes task args through a shell without quoting, so paths with spaces break the tasks.
- The one-off paste goes through the clipboard and the focused herdr-app terminal.
- `hc ls` reports the terminal's launch folder, so an agent that `cd`s elsewhere matches its launch repo.
