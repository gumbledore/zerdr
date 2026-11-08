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
| Zed (editor) | `ctrl-shift-space` | `zh add`: queue the selection (or cursor line) in the repo's review batch with a one-line note (`omarchy-menu-input`; Esc = no note); notifies the queued count |
| Zed (editor) | `ctrl-space` with a batch | submit the batch (paste + Enter) and focus the agent; with a selection, prompt its note, append it, then submit all |
| Zed task | "herdr: clear batch" | `zh clear`: discard the batch |

Batch message (selections trimmed to 20 lines, `...` marks the cut):

````
Review comments:

1. @src/a.txt#L2-3
```
two
three
```
first note

2. @src/a.txt#L4
```
four
```
````

A blocked agent keeps the batch (focus + notification). A working agent receives it (it queues).
The batch is submitted with `hc send <terminal>` (paste + Enter by id, never `--force`) and cleared
only when that succeeds; a failed focus or send keeps it. `add`, `clear` and batch submit run under
`flock` on `~/.local/state/zerdr/batch/.lock`, so quick repeated presses cannot double-submit or lose items.


Pasted format (the code fence keeps multi-line selections intact):

````
@src/a.txt#L2-3
```
two
three
```
````

**Target agent**: local, live, status-reporting terminals from `hc ls --json` whose cwd's git
root equals the root of the active file's directory (worktrees are their own root, even nested ones).
The current folder is `foreground.cwd` from `hc get <t> --json` (falling back to `cwd`). The agent last focused in herdr-app
wins if it is in that set, else blocked > done > working > idle. Remote agents are never targeted.
A blocked agent gets no paste: it is focused and a notification says so. No agent: notification.

**Paste without Enter**: `hc send` always presses Enter and `hc keys` cannot type arbitrary text,
so the one-off paste focuses the agent, copies the text with `wl-copy`, runs
`herdr-app do terminal.paste` and restores the clipboard (with its MIME type; an empty one is cleared).
A failed focus or paste is reported by notification.

State: `~/.local/state/zerdr/batch/<sha1 of git root>.json` (items `{path, lines, selection, note}`).

## Install

```sh
./install.sh   # writes Zed tasks/keymap if absent, links the herdr-app mod
```

Then add the herdr-app keys it prints and put the mod in a layout, e.g. a 1px block
`{"type":"block","size":{"px":1},"content":{"mod":"zerdr"}}`.

Config (env): `ZH_TERMINAL_CLASS` (Hyprland class to raise; default `herdr-app`).
Needs `hc`, `herdr-app`, `jq`, `wl-clipboard`, `hyprctl`, `notify-send`, `omarchy-menu-input`.

Add the following to local claude settings to allow writing to installed location if working with a development copy:

```{
  "sandbox": {
    "filesystem": {
      "allowWrite": ["~/.local/share/zerdr"]
    }
  }
}
```

## Known limits

- The tasks pass only `$ZED_WORKTREE_ROOT`; `zh` reads `ZED_FILE`, `ZED_ROW`, `ZED_SELECTED_TEXT` from the task env
  (positional `root file row` still work as a fallback). With no active editor, selection paths just focus/submit and `add` notifies and exits.
- The one-off paste goes through the clipboard and the focused herdr-app terminal.
