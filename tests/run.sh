#!/bin/bash
# Runs every test against stubbed hc/herdr-app/notify-send/hyprctl/wl-clipboard.
set -uo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
rc=0
for t in zh; do
  bash "$ROOT/$t-test.sh" || rc=1
done
exit $rc
