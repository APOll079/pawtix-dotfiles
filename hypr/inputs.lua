---@module 'hl'
-- =========================
-- INPUTS: keyboard layout, pointer settings and mouse-button binds
-- =========================

hl.config({
    input = {
        kb_layout = "se",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = -0.5 -- -1.0 - 1.0, 0 means no modification.
    }
})

-- mainMod + LMB drags a window
hl.bind(mainMod .. " + " .. "mouse:272", hl.dsp.window.drag(), { mouse = true })  -- help: Mouse | Drag a window

-- Side buttons: drag (276) and fullscreen (275) with no modifier
local sideDragBind = hl.bind("mouse:276", hl.dsp.window.drag(), { mouse = true })  -- help: Mouse | Drag a window
local sideFullscreenBind = hl.bind("mouse:275", hl.dsp.window.fullscreen({ mode = 1 }))  -- help: Mouse | Maximise window

-- Game mode: SUPER + G turns the bare side-button binds off (and back on) so games get the raw buttons
local gameMode = false
hl.bind(mainMod .. " + G", function()  -- help: Desktop | Game mode (side buttons)
    gameMode = not gameMode
    sideDragBind:set_enabled(not gameMode)
    sideFullscreenBind:set_enabled(not gameMode)
    hl.dispatch(hl.dsp.exec_cmd("notify-send 'Game mode' '" .. (gameMode and "side buttons off" or "side buttons on") .. "'"))
end)
