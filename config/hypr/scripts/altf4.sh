#!/usr/bin/env bash
# alt+f4, the windows way -- bound in hyprland/keybinds.lua, which can only
# name one action per key, so the deciding happens here:
#
#   the power menu is up  -> it closes (it is a layer, not a window: without
#                            this check the key would close the window under it)
#   a window is focused   -> it closes, the same action as super+q
#   nothing is focused    -> the desktop / home screen is up, so the power
#                            menu opens instead (lock, sleep, shut down,
#                            reboot, log out -- power/Power.qml, over ipc)
#
# The shell being down degrades quietly: the ipc calls fail, the window
# branch still works, and there is no power menu to open anyway.

qsc() { qs -p "$HOME/.config/quickshell/galaga" ipc call "$@"; }

if [ "$(qsc power shown 2>/dev/null | tr -d '[:space:]')" = "true" ]; then
    qsc power toggle >/dev/null 2>&1
elif hyprctl activewindow -j 2>/dev/null | jq -e '.address' >/dev/null 2>&1; then
    hyprctl dispatch "hl.dsp.window.close()" >/dev/null 2>&1
else
    qsc power toggle >/dev/null 2>&1
fi
