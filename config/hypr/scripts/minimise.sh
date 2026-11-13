#!/usr/bin/env bash
# minimise: THE entry point for minimising a window in this rice. Every park
# path comes through here -- the white title-bar button (hyprland/titlebars.lua),
# Super+Alt+M (functions.minimise_active runs this), and show-desktop.sh, once
# per window. Minimise in Hyprland = park on special:minimized.
#
# Before parking, the window is offered to the galaga shell (genie/Genie.qml):
# it snapshots the window's pixels and warps them down into the deck's
# minimised section -- the genie effect. The shell takes ownership of the park
# by answering "go" to the IPC call; it then captures, shows the ghost, and
# dispatches the park itself (with its own fallback timer, so the park lands
# even if the snapshot fails). ANY other outcome -- galaga not the running
# shell, the effect off in settings (settings -> features -> genie), a shell too old
# to have the handler, qs missing -- and this script parks the window directly,
# exactly as the rice always did. Minimising never depends on the effect.
#
# usage: minimise.sh [address]     (no address: the active window)

addr=$1
if [ -n "$addr" ]; then
    win=$(hyprctl clients -j 2>/dev/null | jq -c --arg a "$addr" 'map(select(.address == $a)) | .[0] // empty')
else
    win=$(hyprctl activewindow -j 2>/dev/null | jq -c 'select(.address) // empty')
fi
[ -n "$win" ] || exit 0

# already on the park: a second park is a no-op in hypr too, but skip the
# IPC round trip (and a ghost of a window that is not even visible)
[ "$(printf '%s' "$win" | jq -r '.workspace.name // empty')" = "special:minimized" ] && exit 0

# the request the shell needs: address, geometry at park time (global logical
# px, the space grim -g works in), and the monitor NAME (clients report the
# id; the shell finds its screen by name)
monid=$(printf '%s' "$win" | jq -r '.monitor // -1')
mon=$(hyprctl monitors -j 2>/dev/null | jq -r --argjson id "$monid" 'map(select(.id == $id)) | .[0].name // empty')
req=$(printf '%s' "$win" | jq -c --arg m "$mon" '{ address: .address, at: .at, size: .size, monitor: $m }')

ans=$(timeout 2 qs -p "$HOME/.config/quickshell/galaga" ipc call genie minimise "$req" 2>/dev/null | tr -d '[:space:]')
[ "$ans" = "go" ] && exit 0

addr=$(printf '%s' "$win" | jq -r '.address')
hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = \"special:minimized\", follow = false })" >/dev/null 2>&1
