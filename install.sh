#!/usr/bin/env bash
# Link the herdr-app mod; install Zed tasks/keymap (never overwrites).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
zed=${XDG_CONFIG_HOME:-$HOME/.config}/zed

mkdir -p "$zed"
for f in tasks keymap; do
  src=$(sed "s|@ZH@|$here/bin/zh|" "$here/zed/$f.json")
  if [[ -e $zed/$f.json ]]; then
    echo "-- $zed/$f.json exists; merge this in by hand:"; echo "$src"
  else
    echo "$src" >"$zed/$f.json" && echo "wrote $zed/$f.json"
  fi
done

mods=${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app/mods
mkdir -p "$mods"
ln -sfn "$here/herdr-app/zerdr" "$mods/zerdr" && echo "linked herdr-app mod zerdr"

cat <<'MSG'

Add to ~/.config/herdr-app/keys.json ("global"):
  "alt-z": "zerdr.open",
  "alt-shift-z": "zerdr.review"
MSG
