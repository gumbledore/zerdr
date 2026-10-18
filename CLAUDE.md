# zerdr

herdr plugin + Zed glue: review an agent's work in Zed once it lands, and jump between
a Zed window and its herdr agent. Everything matches on the git toplevel. See README.md
for the user-facing actions and known limits.

## Layout

- `bin/zh`: the only code. One bash CLI: herdr actions (`open`, `review`, `commits`),
  the agent-done event hook (`done`), and Zed tasks (`focus`, `mention`).
- `herdr-plugin.toml`: plugin `kmg.zed`. Action ids are bound in herdr's config as
  `kmg.zed.<action>`, so renaming the id or actions breaks those keybindings.
- `zed/tasks.json`, `zed/keymap.json`: templates. `@ZH@` gets replaced with the path to `zh`.
- `install.sh`: for other people. Kevin's machines get set up from dotfiles instead (below).

## Dev vs installed copy

- This checkout is for development. The installed copy is `~/.local/share/zerdr`,
  a clone that herdr links (`herdr plugin list`). It updates through
  `git -C ~/.local/share/zerdr pull` or `~/dotfiles/bootstrap.sh`, so push first.
- The live Zed keymap/tasks and herdr keys are stowed from `~/dotfiles`
  (`stow/zed`, `stow/herdr`). Editing `zed/*.json` here doesn't change the machine;
  mirror any change there.

## Conventions

- Bash with `set -euo pipefail`, plus `jq` for herdr's JSON output. No other dependencies.
- Keep it small. Prefer deleting over adding. The Claude Code IDE bridge was
  removed on purpose (Claude's terminal diff is enough), so don't bring it back.
- Zed task args go through a shell unquoted, so the selection is read from
  `$ZED_SELECTED_TEXT` rather than args.

## Checking changes

No test suite. At minimum:

- `bash -n bin/zh`, and `bin/zh` with no args prints the usage.
- Fake herdr: `HERDR_BIN_PATH=./fake-herdr bin/zh mention ...`, with a script that answers
  `agent list` / `pane send-text`. Fake Zed: `ZED_BIN=echo`.
- Say which commands were not run against live herdr/Zed.
