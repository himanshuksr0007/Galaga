hl.config({
    animations = {
        enabled = true,
    },
})

-- Motion register, matched to the shell's own (Theme.qml: 350 ms, ease-out glide):
-- short, out-curves, hard stops -- nothing drifts or overshoots. Speeds are in
-- 100 ms units. Outs are the fastest thing on screen (a close should feel instant),
-- ins a touch slower, moves in between: the minimise park, maximise and restores
-- all ride windowsMove, so that leaf sets how deliberate the buttons feel.
-- Only leaves the current animation tree has are configured here (there is no
-- fullscreen leaf -- fullscreen changes ride windowsMove like every geometry change).

-- Animation curves
hl.curve("emphasizedAccel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("emphasizedDecel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })

-- Animation configs
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3, bezier = "emphasizedAccel", style = "slide" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 4, bezier = "standard" })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 4, bezier = "emphasizedDecel" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "emphasizedAccel" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "standard" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "standard", style = "slidevert" })

hl.animation({
    leaf    = "specialWorkspace",
    enabled = true,
    speed   = 3,
    bezier  = "emphasizedDecel",
    style   = "slidefadevert 15%"
})
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "standard" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 4, bezier = "standard" })
hl.animation({ leaf = "border", enabled = true, speed = 3, bezier = "standard" })
