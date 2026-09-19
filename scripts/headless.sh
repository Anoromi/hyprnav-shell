#!/usr/bin/env bash
# Create or remove the headless Hyprland output used for development.
# Usage: headless.sh up|down|status   (name defaults to HEADLESS-QS)
set -euo pipefail
NAME="${HNS_SCREEN:-HEADLESS-QS}"
case "${1:-status}" in
  up)
    if ! hyprctl monitors -j | grep -q "\"name\": \"$NAME\""; then
      hyprctl output create headless "$NAME" >/dev/null
      sleep 0.4
    fi
    hyprctl eval "hl.monitor({ output = \"$NAME\", mode = \"1920x1080@60\", position = \"auto-right\", scale = 1 })" >/dev/null
    sleep 0.3
    hyprctl monitors -j | python3 -c "import json,sys; [print(m['name'],m['width'],m['height'],'scale',m['scale'],'at',m['x'],m['y'],'ws',m['activeWorkspace']['id']) for m in json.load(sys.stdin) if m['name']=='$NAME']"
    ;;
  down) hyprctl output remove "$NAME" ;;
  status) hyprctl monitors -j | python3 -c "import json,sys; [print(m['name'],m['width'],m['height'],m['scale'],m['activeWorkspace']['id']) for m in json.load(sys.stdin)]" ;;
esac
