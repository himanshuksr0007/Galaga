local scheme = require("scheme.demonshot")
local home   = os.getenv("HOME")

-- DEMONSHOT_NESTED=1 Hyprland -c .../rice/config/hypr/hyprland.lua -- nested session for debugging:
-- the system daemons are already running outside
local nested = os.getenv("DEMONSHOT_NESTED") ~= nil
-- which shell is alive (demonshot, glyph...), decided by rice: `rice switch <name>` or the Rice app.
-- Full path: hypr does not have ~/.local/bin in PATH
local rice   = home .. "/.config/quickshell/rice/rice"

return {
    ------------------
    ---- HYPRLAND ----
    ------------------

    nested                     = nested,

    -- Shell
    rice                       = rice,
    lockCmd                    = rice .. " lock", -- locks the current shell; a second one does not start

    -- Apps
    terminal                   = "kitty -1", -- single-instance: new windows from the live process, ~40 ms instead of ~400
    browser                    = "zen-browser",
    fileExplorer               = "thunar",
    audioSettings              = "pavucontrol",
    -- special-workspace apps (launched if the workspace is empty) and the editor. Keybinds read them on press,
    -- so put yours in user.lua: require("variables").apps.editor = "codium". Not installed -- an empty
    -- workspace opens. telegram and spotify are installed by install.sh --with
    apps                       = {
        sysmon        = "kitty --class btop -T btop btop",
        music         = "spotify-launcher",
        communication = "Telegram",
    },

    -- Touchpad
    touchpadDisableTyping      = false,
    touchpadScrollFactor       = 0.3,
    gestureFingers             = 3,
    overviewFingers            = 4, -- the desktops overview: 4 fingers up, as on Windows (gestures.lua)
    workspaceSwipeFingers      = 3, -- the Windows-style set: 3 fingers drive the desktops (gestures.lua)
    gestureFingersMore         = 5,

    -- Blur
    blurEnabled                = true,
    blurSpecialWs              = false,
    blurPopups                 = true,
    blurInputMethods           = true,
    blurSize                   = 8,
    blurPasses                 = 2,
    blurXray                   = false,

    -- Shadow
    -- soft red glow around focus
    shadowEnabled              = true,
    shadowRange                = 10,
    shadowRenderPower          = 4,
    shadowColour               = "rgba(" .. scheme.crimson .. "20)",

    -- Gaps
    workspaceGaps              = 15,
    windowGapsIn               = 6,
    windowGapsOut              = 14,

    -- Window styling
    windowOpacity              = 1,
    windowRounding             = 0,
    windowBorderSize           = 2,
    activeWindowBorderColour   = {
        colors = { "rgb(" .. scheme.crimson .. ")", "rgb(" .. scheme.rose .. ")", "rgb(" .. scheme.crimson .. ")" },
        angle = 135,
    },
    inactiveWindowBorderColour = "rgb(" .. scheme.wine .. ")",

    -- Misc
    volumeStep                 = 5,
    volumeMax                  = 100,
    cursorTheme                = "Bibata-Modern-Classic",
    cursorSize                 = 23,
    sleepGestureCmd            = "systemctl suspend-then-hibernate || systemctl suspend", -- no hibernation -- regular sleep
    showDesktopCmd             = "bash $HOME/.config/hypr/scripts/show-desktop.sh", -- 3-finger swipe down: park this workspace's windows
    minimiseCmd                = "bash $HOME/.config/hypr/scripts/minimise.sh", -- THE minimise entry point: every park path runs this (scripts/minimise.sh)

    ------------------
    ---- KEYBINDS ----
    ------------------

    -- Workspaces
    kbMoveWinToWs              = "SUPER + ALT",
    kbMoveWinToWsGroup         = "CTRL + SUPER + ALT",
    kbGoToWs                   = "SUPER",
    kbGoToWsGroup              = "CTRL + SUPER",
    kbNextWs                   = "CTRL + SUPER + Right",
    kbPrevWs                   = "CTRL + SUPER + Left",

    -- Window Group
    kbWindowGroupCycleNext     = "ALT + TAB",
    kbWindowGroupCyclePrev     = "SHIFT + ALT + TAB",
    kbUngroup                  = "SUPER + U",
    kbToggleGroup              = "SUPER + Comma",

    -- Window Action
    kbMoveWindow               = "SUPER + Z",
    kbResizeWindow             = "SUPER + X",
    kbWindowPip                = "SUPER + ALT + backslash",
    kbPinWindow                = "SUPER + SHIFT + P", -- Super+P -- vpn panel
    kbWindowFullscreen         = "SUPER + F",
    kbWindowBorderedFullscreen = "SUPER + ALT + F",
    kbMinimiseWindow           = "SUPER + ALT + M", -- no minimise in hypr: parks the window on special:minimized
    kbMinimisedWs              = "SUPER + ALT + SHIFT + M", -- peek at the minimised windows
    kbToggleWindowFloating     = "SUPER + ALT + space",
    kbCloseWindow              = "SUPER + Q",

    -- Special workspaces toggles
    kbSpecialWs                = "SUPER + S",
    kbSystemMonitorWs          = "CTRL + SHIFT + Escape",
    kbMusicWs                  = "SUPER + M",
    kbCommunicationWs          = "SUPER + D",
    kbTodoWs                   = "SUPER + R",

    -- Apps
    kbTerminal                 = "SUPER + T",
    kbBrowser                  = "SUPER + W",
    kbEditor                   = "SUPER + SHIFT + K",
    kbFileExplorer             = "SUPER + E",

    -- Misc
    kbSession                  = "CTRL + ALT + Delete",
    kbPower                    = "SUPER + Escape",
    kbAltar                    = "SUPER + Space",
    kbLock                     = "SUPER + L",
    kbRestoreLock              = "SUPER + ALT + L",
}
