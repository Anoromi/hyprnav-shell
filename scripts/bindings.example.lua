-- Example Hyprland (Lua config) binds for hyprnav-shell. Adjust the -p path.
local qs = "qs -p " .. os.getenv("HOME") .. "/code/experiments/hyprnav-shell/shell ipc call "
hl.bind("ALT + TAB", hl.dsp.exec(qs .. "switcher open"))
hl.bind("ALT + SHIFT + TAB", hl.dsp.exec(qs .. "switcher back"))
hl.bind("SUPER + G", hl.dsp.exec(qs .. "grid toggle"))
hl.bind("SUPER + Q", hl.dsp.exec(qs .. "qs toggle"))
