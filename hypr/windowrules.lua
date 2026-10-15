---@module 'hl'

-- =========================
-- WINDOW RULES
-- =========================

hl.window_rule({
    name  = "windowrule-1",
    match = {
        class = ".*"
    },
    suppress_event = "maximize"
})

hl.window_rule({
    name  = "windowrule-2",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false
    },
    no_focus = true
})

-- Float Nemo dialogs
hl.window_rule({
    name  = "windowrule-3",
    match = {
        class = "^nemo$",
        title = "^(.*Properties.*)$"
    },
    float = true
})

-- Make portal dialogs float (file pickers, screen-share picker). Classes are e.g.
-- xdg-desktop-portal-gtk / xdg-desktop-portal-hyprland, so match the prefix
hl.window_rule({
    name  = "windowrule-4",
    match = {
        class = "^(xdg-desktop-portal.*)$"
    },
    float = true
})

hl.window_rule({
    name  = "windowrule-imageviewer",
    match = {
        class = "^(ImageViewer)$"
    },
    float = true
})

-- Make GNOME Image Viewer (Loupe) float
hl.window_rule({
    name = "windowrule-loupe",
    match = {
        initial_class = [[^(org\.gnome\.Loupe)$]],
        initial_title = [[^(Image Viewer)$]]
    },
    float = true
})

hl.window_rule({
    name  = "windowrule-zen-download",
    match = {
        class = "^(zen|zen-browser)$",
        title = "^(.*Downloads.*)$"
    },
    float = true
})

-- Spotify + Vesktop live in the SUPER + C scratchpad (silent: don't steal focus on launch)
hl.window_rule({
    name  = "spotify-scratchpad",
    match = {
        class = "^Spotify$"
    },
    workspace = "special:spotifyspace silent"
})

hl.window_rule({
    name  = "vesktop-scratchpad",
    match = {
        class = "^vesktop$"
    },
    workspace = "special:spotifyspace silent"
})

-- Steam games (and Steam shortcuts) run as steam_app_<id> under Proton: open them on workspace 2 (DP-2)
hl.window_rule({
    name  = "games-workspace",
    match = {
        class = "^steam_app_\\d+$"
    },
    workspace = "2"
})

hl.window_rule({
    name  = "float-on-7zfm",
    match = {
        initial_class = "7zFM"
    },
    float = true
})

-- Float VLC (class is "vlc" on Qt builds; GUESS, not seen running here)
hl.window_rule({
    name  = "float-on-vlc",
    match = {
        class = "^(vlc|VLC)$"
    },
    float = true
})

-- HyprEmoji (SUPER + period): float near the cursor. Rule taken from the package's own
-- /usr/share/hypremoji/hypremoji.lua; without it the picker tiles and fills half the screen.
hl.window_rule({
    name  = "float-on-hypremoji",
    match = {
        title = "^(HyprEmoji)$"
    },
    float = true,
    move  = { "cursor_x-(window_w*0.5)", "cursor_y-(window_h*0.05)" }
})

-- Close HyprEmoji once it loses focus (follow_mouse = 1, so moving onto another window does it).
-- Only after it has had focus once, so it is not killed while it is still opening.
local emojiHadFocus = false
hl.on("window.active", function()
    local open, focused = false, false
    for _, w in ipairs(hl.get_windows()) do
        if w.title == "HyprEmoji" then
            open = true
            if w.active then
                focused = true
            end
        end
    end
    if focused then
        emojiHadFocus = true
    elseif open and emojiHadFocus then
        emojiHadFocus = false
        hl.dispatch(hl.dsp.exec_cmd("pkill -x hypremoji"))
    elseif not open then
        emojiHadFocus = false
    end
end)
