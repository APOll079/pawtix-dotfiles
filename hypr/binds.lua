---@module 'hl'
-- =========================
-- KEYBINDINGS / WORKSPACES
-- (keyboard layout and mouse buttons live in inputs.lua)
-- =========================

hl.bind(mainMod .. " + " .. "D", hl.dsp.exec_cmd(menu))  -- help: Apps | Launcher
-- Super+Q closes an open quickshell menu first (any monitor); only with no menu open does it close the window
local closeMenuOrWindow = [[bash -c 'for m in $(hyprctl monitors -j | jq -r ".[].name"); do qs ipc call menus_$m closeAny; done | grep -q true || hyprctl dispatch "hl.dsp.window.close()"']]
hl.bind(mainMod .. " + " .. "q", hl.dsp.exec_cmd(closeMenuOrWindow))  -- help: Windows | Close menu, else close window
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = 1 }))  -- help: Windows | Maximise
hl.bind(mainMod .. " + SHIFT" .. " + " .. "F", hl.dsp.window.fullscreen())  -- help: Windows | Fullscreen
hl.bind(mainMod .. " + " .. "return", hl.dsp.exec_cmd(terminal))  -- help: Apps | Terminal
hl.bind(mainMod .. " + " .. "E", hl.dsp.exec_cmd(fileManager))  -- help: Apps | File manager
hl.bind(mainMod .. " + " .. "B", hl.dsp.exec_cmd("zen-browser"))  -- help: Apps | Browser
hl.bind(mainMod .. " + " .. "space", hl.dsp.window.float({ action = "toggle" }))  -- help: Windows | Toggle floating
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("hypremoji"))  -- help: Apps | Emoji picker

-- Snipping overlay on the focused monitor (quickshell ScreenshotOverlay.qml)
local screenshotOverlay = [[bash -c 'qs ipc call screenshot_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]
hl.bind(mainMod .. " + SHIFT" .. " + " .. "S", hl.dsp.exec_cmd(screenshotOverlay))  -- help: Screen | Screenshot overlay
-- Games menu (quickshell GamesMenu.qml) on the focused monitor
local gamesMenu = [[bash -c 'qs ipc call games_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]
hl.bind(mainMod .. " + SHIFT" .. " + " .. "G", hl.dsp.exec_cmd(gamesMenu))  -- help: Apps | Games menu
hl.bind(mainMod .. " + SHIFT" .. " + " .. "c", hl.dsp.exec_cmd("hyprpicker -a"))  -- help: Screen | Pick a colour
-- Task Manager (quickshell TaskManager.qml) on the focused monitor; btm stays installed, unbound
local taskManager = [[bash -c 'qs ipc call taskmanager_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]
hl.bind("CTRL + SHIFT" .. " + " .. "ESCAPE", hl.dsp.exec_cmd(taskManager))  -- help: Apps | Task Manager
-- Spotify panel (quickshell SpotifyPanel.qml) on the focused monitor
local spotifyPanel = [[bash -c 'qs ipc call spotify_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]
hl.bind(mainMod .. " + " .. "S", hl.dsp.exec_cmd(spotifyPanel))  -- help: Apps | Spotify panel
-- Keybind cheat sheet (quickshell CheatSheet.qml)
local cheatSheet = [[bash -c 'qs ipc call cheatsheet_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd(cheatSheet))  -- help: Desktop | This cheat sheet
-- Clipboard history lives in the quickshell launcher (themed, keyboard-driven)
hl.bind(mainMod .. " + " .. "V", hl.dsp.exec_cmd([[bash -c 'qs ipc call appLauncher_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") clipboard']]))  -- help: Apps | Clipboard history
hl.bind(mainMod .. " + " .. "L", hl.dsp.exec_cmd("hyprlock"))  -- help: Desktop | Lock screen
hl.bind(mainMod .. " + " .. "N", hl.dsp.exec_cmd([[bash -c 'qs ipc call notifications_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggle']]))  -- help: Desktop | Side panel (notifications)

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + " .. "left", hl.dsp.focus({ direction = "left" }))  -- help: Windows | Focus left
hl.bind(mainMod .. " + " .. "right", hl.dsp.focus({ direction = "right" }))  -- help: Windows | Focus right
hl.bind(mainMod .. " + " .. "up", hl.dsp.focus({ direction = "up" }))  -- help: Windows | Focus up
hl.bind(mainMod .. " + " .. "down", hl.dsp.focus({ direction = "down" }))  -- help: Windows | Focus down

-- Workspaces 1-4 live on the main monitor: mainMod + N switches, mainMod + SHIFT + N moves the active window
for i = 1, 4 do
    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))  -- help: Workspaces | Go to workspace
    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))  -- help: Workspaces | Move window to workspace
    hl.workspace_rule({
        workspace = tostring(i),
        monitor = "DP-2",
        default = (i == 1)
    })
end

-- Top monitor: one fixed workspace that none of the number binds ever switch
hl.workspace_rule({
    workspace = "11",
    monitor = "DP-1",
    default = true,
    persistent = true
})

hl.bind(mainMod .. " + " .. "mouse_down", hl.dsp.focus({ workspace = "e+1" }))  -- help: Workspaces | Next workspace
hl.bind(mainMod .. " + " .. "mouse_up", hl.dsp.focus({ workspace = "e-1" }))  -- help: Workspaces | Previous workspace

-- SUPER + C: scratchpad for Spotify + Vesktop. The window rules in windowrules.lua
-- send both to special:spotifyspace; this launches whichever isn't running, then toggles it.
local scratchApps = {
    { class = "Spotify", cmd = "spotify" },
    { class = "vesktop", cmd = "vesktop" }
}
hl.bind(mainMod .. " + " .. "C", function()  -- help: Desktop | Spotify + Vesktop scratchpad
    local running = {}
    for _, w in ipairs(hl.get_windows()) do
        running[w.class] = true
    end
    for _, app in ipairs(scratchApps) do
        if not running[app.class] then
            hl.dispatch(hl.dsp.exec_cmd(app.cmd))
        end
    end
    hl.dispatch(hl.dsp.workspace.toggle_special("spotifyspace"))
end)

local screenshotCmd = "bash -c 'file=$HOME/screenshots/screenshot_$(date +%Y%m%d_%H%M%S).png && mkdir -p $HOME/screenshots && grim $file && wl-copy < $file'"
-- Print (and SUPER + SHIFT + S, above) open the quickshell snipping overlay on the focused
-- monitor: region drag, window, screen, all, history. F12 stays instant
hl.bind("Print", hl.dsp.exec_cmd(screenshotOverlay))  -- help: Screen | Screenshot overlay
hl.bind("F12", hl.dsp.exec_cmd(screenshotCmd))  -- help: Screen | Instant full screenshot

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl -p spotify play-pause"), { locked = true })  -- help: Media | Play / pause Spotify
