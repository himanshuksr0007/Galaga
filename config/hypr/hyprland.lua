-- Monitor: hypr decides the scale (the shell then applies it too, Rules.monitor)
hl.monitor({ output = "", mode = "highres", position = "auto", scale = "auto" })

-- XWayland is scaled by hypr: blurry on HiDPI, but the size is correct at any scale. Crisp at integer scale -- in user.lua:
--   hl.config({ xwayland = { force_zero_scaling = true } }); hl.env("GDK_SCALE", "2")

-- Configs
require("hyprland.env")
require("hyprland.general")
require("hyprland.input")
require("hyprland.misc")
require("hyprland.animations")
require("hyprland.decoration")
require("hyprland.titlebars")
require("hyprland.group")
require("hyprland.execs")
require("hyprland.rules")
require("hyprland.gestures")
require("hyprland.keybinds")

-- your own keybinds and overrides on top of the rice: hypr/user.lua (in .gitignore, repo updates leave it alone)
local user = io.open(os.getenv("HOME") .. "/.config/hypr/user.lua")
if user then user:close(); require("user") end
