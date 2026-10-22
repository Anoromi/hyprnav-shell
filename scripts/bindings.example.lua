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

-- Ctrl+Tab across every browser's tabs, most recently used first (needs a
-- browser-tabs host per browser, see services/BrowserTabs.qml). The keys go
-- to the shell only while a browser is in front, or while a cycle runs and
-- the shell's list holds the keyboard; other windows get Ctrl+Tab as usual.
-- The Ctrl release commits.
local browserClasses = {
    ["island-browser"] = true, ["zen-beta"] = true, zen = true,
    chromium = true, ["chromium-browser"] = true,
}
local tabsCycling = false
local function frontBrowser()
    local window = hl.get_active_window()
    return window ~= nil and browserClasses[window.class] == true, window
end
local function tabsStep(name, mods)
    return function()
        local isBrowser, window = frontBrowser()
        if tabsCycling or isBrowser then
            tabsCycling = true
            hl.dispatch(hl.dsp.global("hyprnav-shell:" .. name))
        elseif window ~= nil then
            hl.dispatch(hl.dsp.send_shortcut({ mods = mods, key = "Tab", window = window }))
        end
    end
end
hl.bind("CTRL + Tab", tabsStep("tabs-next", "CTRL"))
hl.bind("CTRL + SHIFT + Tab", tabsStep("tabs-prev", "CTRL SHIFT"))
local function tabsCommit()
    if not tabsCycling then
        return
    end
    tabsCycling = false
    hl.dispatch(hl.dsp.global("hyprnav-shell:tabs-commit"))
end
for _, key in ipairs({ "Control_L", "Control_R" }) do
    hl.bind(key, tabsCommit, { release = true, non_consuming = true, transparent = true })
    hl.bind("CTRL + " .. key, tabsCommit, { release = true, non_consuming = true, transparent = true })
end
-- Copy the front browser tab's address; the window still gets the key.
hl.bind("CTRL + SHIFT + C", function()
    if frontBrowser() then
        hl.dispatch(hl.dsp.global("hyprnav-shell:tabs-copy-url"))
    end
end, { non_consuming = true })

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
