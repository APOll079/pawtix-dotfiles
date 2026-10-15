---@module 'hl'
-- =========================
-- AUTOSTART
-- =========================
hl.on("hyprland.start", function()
    -- Use --all instead of --systemd for Artix/dinit
    hl.exec_cmd("dbus-update-activation-environment --all")

    -- dinit user services
    hl.exec_cmd("dinitctl start pipewire")
    hl.exec_cmd("dinitctl start wireplumber")

    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("zen-browser")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("flatpak run com.github.wwmm.easyeffects --gapplication-service")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("kdeconnectd")  -- phone link (Start > Phone)
    hl.exec_cmd("quickshell")

    -- Lock right after login, only if ~/.config/hypr/lock-at-login exists (install.sh creates it
    -- when you answer yes; delete the file to turn it off)
    local marker = io.open((os.getenv("HOME") or "") .. "/.config/hypr/lock-at-login", "r")
    if marker then
        marker:close()
        hl.exec_cmd("hyprlock")
    end
end)
