# Galaga colour picker

Press **Super+Shift+C**, point at a pixel and left-click to copy its hex value and close. The circular pixel loupe sits in a curved cutout with a transparent gap around it. The overlay opens and closes instantly. The dot-matrix meter follows the pointer and flips sides near screen edges. Switch off **Settings → Features → colour picker card** to use the original hyprpicker. Super+Shift+D is free.

Like the original picker, Galaga samples a frozen view of the desktop. The picker uses grim directly on Hyprland and opens without a portal or sharing prompt. Reopen it for fresh content. Move across outputs to sample a different display.

**Ctrl+L** or right-click pins the card so its controls are reachable. Cycle between 1×1, 3×3 and 5×5 physical capture pixels, toggle hex/decimal, or copy a 64×64 PNG swatch. Enter or Ctrl+C copies text; Ctrl+Alt+C copies the swatch. Esc cancels. Capture values start unprofiled. The colour-space control lets you explicitly assume sRGB and convert to Adobe RGB.

The bind in `config/hypr/hyprland/keybinds.lua` calls `rice pick`. The CLI opens the feature through its gated IPC handler in `shell.qml` and falls back to `hyprpicker -a` if unavailable. The session worker, `meter/picker.py`, freezes each attached output into an anonymous memory file before `meter/ColourMeter.qml` maps its per-output overlays. The pointer position and the click are mapped against the same captured frame. Clipboard export resamples the click coordinates even if the loupe update is pending.

To check on your desktop, cross a sharp colour boundary, click and paste into an editor. Repeat at the edge of a scaled output. Lock over a pixel and move onto the card: the sample should stay fixed. Cancel with Esc and confirm the clipboard remains intact.
