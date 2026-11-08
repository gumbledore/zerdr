# zerdr

herdr-app mod + Zed glue: open a pane's repo in Zed, and send code from Zed to that
repo's agent. Everything matches on the git toplevel. See README.md for the
user-facing actions and known limits.

## Layout

- `herdr-app/zerdr/`: the mod (`main.js`, `mod.json`). Commands are bound in herdr-app's
  `keys.json` as `zerdr.<command>`, so renaming them breaks those keys. herdr-app writes
  `.d.ts`/`jsconfig.json` here; they are git-ignored.
- `bin/zh`: Zed tasks (`send`, `add`, `clear`), talking to herdr-app and `hc`.
- `zed/tasks.json`, `zed/keymap.json`: templates. `@ZH@` gets replaced with the path to `zh`.
- `install.sh`: links the mod and writes the Zed files if absent. Kevin's machines run it
  from `~/dotfiles/bootstrap.sh`.
- `tests/`: stub-PATH harness for `zh`.

## Dev vs installed copy

- The installed copy is `~/.local/share/zerdr`; `~/.config/herdr-app/mods/zerdr` links to it.
  It updates through `git -C ~/.local/share/zerdr pull` or `~/dotfiles/bootstrap.sh`, so push first.
- The live Zed keymap/tasks and herdr-app keys are stowed from `~/dotfiles`
  (`stow/zed`, `stow/herdr-app`). Editing `zed/*.json` here doesn't change the machine;
  mirror any change there.

## Conventions

- Bash with `set -euo pipefail`, plus `jq`. Keep it small; prefer deleting over adding.
  The Claude Code IDE bridge was removed on purpose, so don't bring it back.
- Zed task args go through a shell unquoted, so `zh` reads `ZED_*` from the env; args are a fallback.
- `@path` refs with spaces are quoted (`@"a b.txt#L1"`), because Claude's parser stops at a space.

## Checking changes

- `bash tests/run.sh` (all must pass) and `bash -n bin/zh`.
- `herdr-app check ~/.config/herdr-app/mods/zerdr` for the mod.
- Say which paths were not tried against live herdr-app/Zed.
