#!/usr/bin/env bash
# Link the herdr plugin, start the bridge, and install Zed tasks/keymap (never overwrites).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
zed=${XDG_CONFIG_HOME:-$HOME/.config}/zed

herdr plugin link "$here" >/dev/null && echo "linked herdr plugin kmg.zed"
"$here/bin/zh" bridge && echo "started Claude Code -> Zed bridge"

for f in tasks keymap; do
  src=$(sed "s|@ZH@|$here/bin/zh|" "$here/zed/$f.json")
  if [[ -e $zed/$f.json ]]; then
    echo "-- $zed/$f.json exists; merge this in by hand:"; echo "$src"
  else
    echo "$src" >"$zed/$f.json" && echo "wrote $zed/$f.json"
  fi
done

cat <<'MSG'

Suggested herdr keybindings (~/.config/herdr/config.toml):
  [[keys.command]]
  key = "prefix+e"
  type = "plugin_action"
  command = "kmg.zed.open"
  description = "open project in Zed"

  [[keys.command]]
  key = "prefix+shift+e"
  type = "plugin_action"
  command = "kmg.zed.review"
  description = "review changes in Zed"

Make Claude connect automatically: run `claude --ide`, or /config -> "Auto-connect to IDE".
MSG
