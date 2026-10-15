---@module 'hl'

--## VARIABLES ###

mainMod = "SUPER"
menu = [[bash -c 'qs ipc call appLauncher_$(hyprctl monitors -j | jq -r ".[] | select(.focused) | .name") toggleAppLauncher']]
terminal = "kitty"
fileManager = "nemo"

require("autostart")
require("monitors")
require("env")
require("look_and_feel")
require("inputs")
require("binds")
require("windowrules")
