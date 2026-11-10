#!/usr/bin/env bash
# show-desktop: park every window on the active workspace into special:minimized --
# the rice's minimise (3-finger swipe down; config/hypr/hyprland/gestures.lua).
# The windows land in the deck's minimised section and come back from there, or
# with the peek/restore binds (Super+Alt+Shift+M). No-op on an empty workspace,
# and on a special workspace itself (parking the park would be nonsense).
# Pinned windows stay: they are meant to be visible on every workspace.
# The dispatch string is the same one the titlebar minimise button runs.

ws=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // empty')
[ -n "$ws" ] && [ "$ws" -gt 0 ] 2>/dev/null || exit 0

hyprctl clients -j 2>/dev/null \
    | jq -r --argjson ws "$ws" '.[] | select(.workspace.id == $ws and (.pinned | not)) | .address' \
    | while IFS= read -r addr; do
        [ -n "$addr" ] || continue
        hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = \"special:minimized\", follow = false })" >/dev/null 2>&1
    done
