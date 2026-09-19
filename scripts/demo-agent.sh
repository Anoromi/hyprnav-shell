#!/usr/bin/env bash
# Fake agent transcript that keeps scrolling, so thumbnails visibly live.
name="${1:-agent}"
msgs=("reading src/server.rs" "running cargo test --lib" "12 passed, 0 failed" "editing protocol.rs: add SlotNameSet" "waiting for compositor event" "hyprctl workspaces -j" "diff applied, 3 files" "fmt check ok" "thinking about slot inheritance" "grep -rn 'inherit' src/" "writing tests/inherit.rs" "build finished in 4.2s")
i=0
while true; do
  m=${msgs[$((RANDOM % ${#msgs[@]}))]}
  printf '\e[2m%s\e[0m \e[33m%s\e[0m  %s\n' "$(date +%H:%M:%S)" "$name" "$m"
  i=$((i+1)); [ $((i % 7)) -eq 0 ] && printf '\e[32m  ok\e[0m step %d complete\n' "$i"
  sleep 0.7
done
