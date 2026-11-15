-- Window drag events, from the hyprdrag plugin (himanshuksr0007/hyprdrag,
-- https://github.com/himanshuksr0007/hyprdrag -- installed and enabled by install.sh
-- through hyprpm).
--
-- Why: Hyprland itself never says when a window drag or resize begins or
-- ends, and the shell wants exactly that -- the deck and the quick panel
-- stay down while a window is carried across their edges, drag-snap tracks
-- the drag, and the deck offers its workspaces as drop targets. The plugin
-- watches the compositor's own drag state and posts it to the event socket:
-- hyprdrag-movestart / hyprdrag-movestop and hyprdrag-resizestart /
-- hyprdrag-resizestop, each with the window's address. The shell listens
-- (services/DragWatch.qml) and, while the events arrive, stops inferring
-- drags from geometry samples; DragWatch keeps the sampling path for when
-- they do not.
--
-- Loading mirrors titlebars.lua: the .so hyprpm built is loaded HERE,
-- during config evaluation, and verified with hl.get_loaded_plugins (the
-- wiki's pattern). The known repo path is tried first, then any other repo
-- dir under ~/.local/share/hyprpm. There is nothing to configure and no
-- permission to grant -- titlebars.lua's hyprpm grant already covers
-- execs.lua's reload fallback. When the plugin is not in (stale after a
-- Hyprland upgrade, or never built), this file only prints its log line:
-- the exec'd reload pass re-runs it with the plugin in, and until then the
-- shell is on its sampling fallback -- degraded, never broken.
local function hyprdrag_so()
    local home = os.getenv("HOME")
    local known = home .. "/.local/share/hyprpm/hyprdrag/hyprdrag.so"
    local f = io.open(known)
    if f then
        f:close()
        return known
    end
    -- pcall'd: this fallback must never be able to break the rest of the file
    local ok, line = pcall(function()
        local ls = io.popen("ls " .. home .. "/.local/share/hyprpm/*/hyprdrag/hyprdrag.so 2>/dev/null")
        if not ls then return nil end
        local l = ls:read("*l")
        ls:close()
        return l
    end)
    if ok and line and line ~= "" then return line end
    return nil
end

local function is_plugin_loaded(name)
    for _, v in pairs(hl.get_loaded_plugins()) do
        if v.name == name then return true end
    end
    return false
end

local so = hyprdrag_so()
if so then pcall(hl.plugin.load, so) end -- already loaded (a re-parse) or stale: either way, not fatal here

if not is_plugin_loaded("hyprdrag") then
    print("galaga: hyprdrag is not loaded at config time -- its drag events wait for the hyprpm reload pass")
end
