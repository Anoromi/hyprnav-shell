-- Example Hyprland (Lua config) binds for hyprnav-shell.
--
-- The switcher and grid keys are global shortcuts the shell registers itself
-- (hyprland-global-shortcuts protocol, app id "hyprnav-shell"), so a key press
-- reaches the shell without starting a process. `hyprctl globalshortcuts`
-- lists them while the shell runs.

-- Hold Super, tap Tab to step through recent workspaces, let go to switch.
hl.bind("SUPER + Tab", hl.dsp.global("hyprnav-shell:switcher-open"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("hyprnav-shell:switcher-back"))
hl.bind("SUPER + A", hl.dsp.global("hyprnav-shell:grid-toggle"))

-- The Super release commits the switcher's selection (a no-op when it is
-- closed). `transparent` keeps Super+Tab from shadowing the release bind, and
-- both modifier states are bound because Hyprland may see the release with
-- Super still held or already gone.
for _, key in ipairs({ "Super_L", "Super_R" }) do
    hl.bind(key, hl.dsp.global("hyprnav-shell:switcher-commit"), { release = true, non_consuming = true, transparent = true })
    hl.bind("SUPER + " .. key, hl.dsp.global("hyprnav-shell:switcher-commit"), { release = true, non_consuming = true, transparent = true })
end

-- No compositor fade on the shell's layers: the shell animates its own, and
-- the default fade held surfaces that map (captions, badges, popups) at part
-- opacity for 200-350 ms. Rule regexes must match the whole namespace.
hl.layer_rule({
    name = "hyprnav-shell-no-animation",
    match = { namespace = "^hyprnav-shell-.*$" },
    no_anim = true,
})

-- Scripts can still drive everything over IPC (this starts a `qs` client,
-- 25-40 ms before the shell sees it, so keep it off hot keys):
local qs = "qs -p " .. os.getenv("HOME") .. "/code/experiments/hyprnav-shell/shell ipc call "
hl.bind("SUPER + Q", hl.dsp.exec_cmd(qs .. "qs toggle"))
