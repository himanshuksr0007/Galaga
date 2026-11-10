// glyph -- window buttons (see README: "Window buttons")
//
// Firefox and Zen draw their own titlebar buttons -- the small grey discs in
// the tab bar -- because on Wayland they put themselves into client-side
// decoration mode no matter what the compositor answers. Those buttons are
// dead on Hyprland: minimise does not exist here and maximise is suppressed,
// so only their close does anything, and gtk.css cannot recolor them (they
// are browser chrome, not GTK titlebuttons).
//
// 0 = never draw the tabs in the titlebar, and draw no built-in buttons
// either -- the window takes the rice's hyprbars bar instead, whose three
// buttons work. This is the same switch as Customize Toolbar -> "Title Bar"
// (ticked). install.sh copies this into every Firefox/Zen profile that does
// not already set the pref; it is read at browser start, so restart the
// browser once after installing. Delete the line to undo.
user_pref("browser.tabs.inTitlebar", 0);
