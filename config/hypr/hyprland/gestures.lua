local vars = require("variables")

-- Trackpad gestures, Windows-style (README: "Gestures"). All native: Hyprland's
-- gesture engine tracks the fingers 1:1, which is what makes the left/right
-- workspace switch follow the hand. The 4-finger tap (quick settings) is the one
-- gesture the native engine has no shape for -- no tap or hold direction exists --
-- so libinput-gestures covers just that one (config/libinput-gestures.conf).
-- To turn gestures off, comment out the hl.gesture lines below (and stop
-- libinput-gestures for the tap).
hl.config({
    gestures = {
        workspace_swipe_distance                 = 700,
        workspace_swipe_cancel_ratio             = 0.15,
        workspace_swipe_min_speed_to_force       = 5,
        workspace_swipe_direction_lock           = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new               = true,
    },
})

-- left / right: previous / next desktop, following the fingers
hl.gesture({ fingers = vars.workspaceSwipeFingers, direction = "horizontal", action = "workspace" })

-- up: the desktops overview (shell module, also on Super+Tab). Four
-- fingers, as on Windows -- three drive the desktops themselves
hl.gesture({
    fingers   = vars.overviewFingers,
    direction = "up",
    action    = function()
        hl.dispatch(hl.dsp.global("shell:desktops"))
    end,
})

-- down: show desktop -- park this workspace's windows into special:minimized
hl.gesture({
    fingers   = vars.gestureFingers,
    direction = "down",
    action    = function()
        hl.exec_cmd(vars.showDesktopCmd)
    end,
})

-- 5-finger down: sleep
hl.gesture({
    fingers   = vars.gestureFingersMore,
    direction = "down",
    action    = function()
        hl.exec_cmd(vars.sleepGestureCmd)
    end,
})
