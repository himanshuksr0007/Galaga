<div align="center">

<img src="assets/title.svg" width="760" alt="Glyph: a Nothing OS rice for Hyprland + Quickshell">

Black, white dots, one red. A sibling of [Demon's Shot](https://github.com/Nebelung-cloud/demons-shot-rice).

My fork of [**glyph-rice**](https://github.com/Nebelung-cloud/glyph-rice) by [**Nebelung-cloud**](https://github.com/Nebelung-cloud) — the rice is his work, this copy just carries my own tweaks (see [Credits](#credits)).

<br>

![Glyph desktop](screenshots/desktop.png)

</div>

<div align="center"><img src="assets/divider-dots.svg" width="720" alt=""></div>

<h2 align="center">What's inside</h2>

| | | |
|---|---|:---:|
| **Bar** | launcher, workspaces, clock, tray | |
| **Home** | clock, greeting, widgets (cava as a round Glyph Matrix), dot grid | |
| **Glyph** | screen edges as OSD: volume, brightness, mic mute, notifications, progress | |
| **Launcher** | apps, commands, windows, calculator, styles, tray apps | `Super` |
| **Quick** | quick settings, game mode, media, notifications; also opens from the right edge | `Super` `A` |
| **Deck** | dashboard from the bottom edge | `Super` `Space` |
| **Desktops** | overview of every desktop that has windows | `Super` `Tab` / swipe up |
| **Prefs** | settings, bar and home layout | `Super` `I` |
| **Shot** | screenshots, editor, recording | `Print` |
| **Clip** | clipboard history | `Super` `V` |
| **Share** | clipboard to the LAN via LocalSend (`localsend-bin`) — files as files, image as png, text as a message | `Super` `Ctrl` `S` |
| **Charms** | emoji, kaomoji, symbols | `Super` `.` |
| **Walls** | wallpapers as dots — or vivid, in their own colours | `Super` `Shift` `W` |
| **VPN** | Clash Verge panel | `Super` `P` |
| **Cal** | calendar, focus timer | click the clock |
| **Buds** | Nothing / CMF earbuds: battery, ANC | |
| **Power** | power menu | `Super` `Esc` |
| **Lock** | lock screen | `Super` `L` |
| **Greeter** | boot login: the lock's face on greetd | `install.sh --greeter` |
| **Rice** | shell switcher, if Demon's Shot is installed too | `rice switch <name>` |

Also: Hyprland (Lua), hypridle, kitty, fish, starship, fastfetch, btop, cava (dots in fish; `command cava` for bars), GTK, Qt and folder colours.

Motion is one register everywhere — short, with a hard stop: the compositor curves
(windows, workspaces, the minimised park and restore) are tuned to the same glide the
shell's surfaces use, and panels rise and fade rather than snap.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Screenshots</h2>

| | |
|:---:|:---:|
| ![launcher](screenshots/launcher.png) **Launcher** | ![quick](screenshots/quick.png) **Quick** |
| ![deck](screenshots/deck.png) **Deck** | ![prefs](screenshots/settings.png) **Prefs** |
| ![shot](screenshots/shot.png) **Shot** | ![clip](screenshots/clip.png) **Clip** |
| ![power](screenshots/power.png) **Power** | |

<div align="center"><img src="assets/divider-matrix.svg" width="720" alt=""></div>

<h2 align="center">Install</h2>

```sh
git clone https://github.com/yasakei/glyph-rice ~/.local/share/glyph
~/.local/share/glyph/install.sh                  # Arch: packages, services, symlinks
~/.local/share/glyph/install.sh --with telegram  # same, extras picked up front
~/.local/share/glyph/install.sh --links          # any distro: symlinks only
~/.local/share/glyph/install.sh --dry-run        # the whole plan printed, nothing changed
~/.local/share/glyph/install.sh --update         # pull, then refresh only what changed
~/.local/share/glyph/install.sh --uninstall      # links away, your old files back
~/.local/share/glyph/install.sh --fix-plasma     # from KDE Plasma: Wi-Fi + autostart fixes
~/.local/share/glyph/install.sh --greeter        # optional, Arch: boot login screen (replaces sddm)
```

Without `--with` it asks everything up front, in lists you tick and pick with the arrow keys —
nothing to type: the file manager (`thunar` or `dolphin`), the login screen (keep yours, or the glyph
face), the mouse (scroll direction, wheel speed, pointer speed --
the same settings as Prefs → INPUT) and which extras to tick: `telegram` (`Super` `D`), `spotify` with
Spicetify (`Super` `M`), `clash` for the VPN panel, `pywalfox` so Firefox follows the palette,
`warp` for Cloudflare WARP (the daemon is enabled for you; its icon sits in the tray) and
`overskride`, a full Bluetooth manager next to the shell's quick panel. The installer also sets
BlueZ's `AutoEnable`, so the Bluetooth adapter powers on with its daemon instead of riding on
whichever app asks first (a power transition mid-connection drops freshly paired earbuds).
One password, then it runs unattended. Old configs go to `~/.dots-backup-<date>/`.
Wallpapers are read from `~/Pictures/Wallpapers`.

| `config/` | goes to |
|---|---|
| `hypr/` | `~/.config/hypr` |
| `quickshell/glyph/` | `~/.config/quickshell/glyph` |
| `quickshell/rice/` | `~/.config/quickshell/rice`, `~/.local/bin/rice` |
| `quickshell/glyph/term/` | `starship.toml` `fastfetch/` `btop/` `cava/` `gtk-*/gtk.css` `qtengine.colors` in `~/.config` |
| `kitty/` `qtengine/` | `~/.config/…` |
| `fish/` | `~/.config/fish` |
| `fonts/` | `~/.local/share/fonts/glyph` |

Monitor, backlight, GPU and sensors are detected. Keyboard layouts are in `hypr/hyprland/input.lua`,
default apps in `hypr/variables.lua`. Earbuds photo: `quickshell/glyph/buds/<device-name>.png`.
Your own binds and overrides go in `hypr/user.lua`: it's gitignored, so `git pull` never touches it.
Apps for the special workspaces and the editor are read when you press the key, so `user.lua` can swap them:

```lua
local apps = require("variables").apps
apps.editor = "codium"              -- Super Shift K, empty by default
apps.todo   = "planify"             -- Super R, empty by default
apps.music  = "spicetify watch -s"  -- Super M, spotify-launcher by default

hl.bind("SUPER + G", hl.dsp.global("shell:game"))  -- game mode has no key by default
```

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Window buttons</h2>

Every window gets the same three buttons, top-left, in the same order: **close** (red),
**minimise** (white), **maximise** (black) — one look, two layers (GTK headerbar apps
are the exception: they render close and maximise — minimise is the one button that
cannot be made real there, for the reasons under "Minimise is not real"):

- **Server-side windows** (terminals, most apps) get a bar from **hyprbars**, the
  hyprland-plugins plugin — `install.sh` adds and enables it through hyprpm, the config is
  `hypr/hyprland/titlebars.lua`. The window's title sits centred in the bar in **Doto**,
  the dot-matrix font from `config/fonts`, bold. The buttons run the same dispatchers as
  the keybinds, so a click animates exactly like the keyboard: close rides `windowsOut`,
  maximise and the minimise move ride `windowsMove` (`hypr/hyprland/animations.lua` — the
  animation tree has no fullscreen leaf, geometry changes are `windowsMove`). The black
  button **maximises** — the window fills the workspace and the bar and gaps stay;
  double-clicking the bar toggles **true fullscreen**. The glyphs are mac-style: the discs
  sit plain and all three glyphs appear only while the cursor hovers one of the buttons
  (hyprbars' `icon_on_hover`; on the GTK side the same reveal is done in CSS).
- **Apps that draw their own buttons** (GTK headerbar apps, Electron) are excluded
  from the bar in `hypr/hyprland/rules.lua` (`hyprbars:no_bar`) and themed instead:
  `quickshell/glyph/term/gtk-3.0` and `gtk-4.0` ship a `settings.ini` and CSS that paints
  the native **close** and **maximise** buttons as the same red and black discs, with
  their glyphs from `term/window-buttons/`. Close and maximise are rendered
  (`gtk-decoration-layout=close,maximize:appmenu`) — and maximise genuinely works:
  the click sends a maximise request, and `rules.lua` exempts exactly these apps from
  its global maximise suppression, so Hyprland honours it (for every other app the
  suppression stays: the tiling layout decides sizes, apps do not maximise
  themselves). Minimise is not rendered: its request can never land — see
  "Minimise is not real" below — so it is not shown at all, rather than painted as a
  disc whose click does nothing. The exclusions are one curated list in `rules.lua`
  (the `ownButtons` list at the top of the file): there is no protocol signal for
  "this app draws its own buttons", so the list is the mechanism. If some app shows
  **both** bars, add it — focus the window, read its class with `hyprctl activewindow`
  (or find it in `hyprctl clients`), add one line to the list: the hyprbar goes away
  and the app's own maximise starts working. GTK4 needs its own
  rules in that CSS: there the button itself is transparent and the visible disc is its
  image node, so colours and glyphs are painted on `windowcontrols button > image` —
  painting the button (the GTK3 way) leaves GTK4 buttons plain grey. **Flatpak** GTK apps
  are sandboxed off from `~/.config/gtk-*` entirely, so `install.sh` also grants the
  installed GNOME flatpaks (Calculator, Nautilus, Text Editor, …) read-only access to the
  two gtk config dirs via `flatpak override --user`; by hand it is
  `flatpak override --user org.gnome.Calculator --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro`,
  then restart the app.
- **Browsers** split in two. **Firefox and Zen** are own-buttons apps, on the same
  `rules.lua` list as the GTK apps: they keep their built-in buttons and get no
  hyprbar. Their button box follows the decoration layout this rice ships for GTK
  (`close,maximize` — no minimise, whose click could not work here), so what they
  draw is exactly the buttons that work: close, and a maximise the suppression
  exemption lets land. Minimise is `Super+Alt+M`, like every own-buttons app.
  (Earlier versions tried the opposite — a `user.js` in every profile switching
  the built-ins off so the hyprbar could take over; the pref kept not reaching
  the profiles that mattered, the Flatpak's above all. `install.sh` now removes
  that snippet from every profile it was ever deployed to — it has to: a profile
  that kept it would draw no buttons of its own *and* get no hyprbar.) For
  **Chromium, Chrome and Brave** nothing changes: there is no file to deploy —
  turn on **Use system title bar and borders** once (Settings → Appearance) and
  they draw no buttons of their own, so the hyprbar takes over there.

**Minimise is not real.** Hyprland has no minimise: the white button (and `Super+Alt+M`)
parks the window on the hidden `special:minimized` workspace. `Super+Alt+Shift+M` peeks at
that workspace — focus a window there and pull it back with any move-to-workspace bind
(`Ctrl+Super+Shift+↓` moves it to the current workspace).

That is also why GTK apps' headerbars show **no minimise disc**. Their own − / ▢
buttons send xdg requests into the compositor, and the two requests have different
fates. **Maximise can land** — it is a real state in Hyprland — and does: the
config's global maximise suppression (`suppress_event = "maximize"` in `rules.lua`,
kept for everything else because the tiling layout decides window sizes) is scoped
to exempt exactly the own-buttons apps, so their ▢ renders as the black disc and
maximises / unmaximises on click. **Minimise cannot land**: the request is received
and dropped — Hyprland has no minimised state to put a window in, and doesn't even
advertise the minimise capability to clients. And nothing outside the compositor
can catch the click on its way down: no IPC event fires for a window's *own*
minimise request (the event socket's `minimized` event only reports an *external*,
taskbar-style client asking to minimise a window), and the plugin API's hooks
mirror those same events, so the point where the request dies is unreachable from
outside. Reaching it would take a custom C++ plugin hooking Hyprland's internal
xdg state handling — and a plugin is built against one Hyprland version's headers
and refuses to load on any other, so it would break on every Hyprland upgrade.
That trade is deliberately not shipped; the keyboard route below is the minimise
story for these apps. There is also no supported way to move those apps onto the
hyprbar instead —
GTK4 ignores `GTK_CSD` on Wayland, libadwaita's headerbar *is* app content (Calculator's
mode switcher and undo/redo live there), and Hyprland has no rule to force a client
into server-side decorations — so the headerbar stays, its working buttons render,
and for GTK apps minimise lives on the keyboard, firing the same dispatchers as the
bar buttons: `Super+Alt+M` parks, `Super+Alt+F` maximises, `Super+F` fullscreens.

Parked windows are listed in the **deck** (bottom edge): a **minimised** section (last
by default — it sits wherever you place it in the deck's section order), behind a
dotted separator, shows each parked window's icon and name — click one and it moves
back to the current workspace, focused. The list is live (it reads the Hyprland
window model directly), scrolls when full, and reads "nothing minimised" in dots
when empty.

**The genie effect.** Parking a window warps it — macOS magic-lamp style — down
into that minimised section. Hyprland's own animations cannot bend a window, so
the shell does it with the window's pixels: every park path (the white button,
`Super+Alt+M`, show-desktop) runs one entry point, `hypr/scripts/minimise.sh`,
which hands the window to the shell *before* parking it. The shell snapshots the
window's rect (`grim`, the screenshot module's capture), lays the snapshot over
the still-live window, parks the real one, and collapses the snapshot into the
minimised section — into the section's **current** place in the deck, computed
from the section order on every park: reorder the sections in settings and the
windows follow the section. Show-desktop's windows warp as a short cascade. If
the shell is not running, or the snapshot fails, the park is a plain park,
exactly as before — the effect can never eat a minimise. Turn the effect off in
**Prefs → FEATURES → genie · minimise**.

**The way back (genie · restore).** Restoring reverses the lamp — with one honest
caveat, stated plainly: a parked window is unmapped, so there are no fresh pixels
to un-warp. What expands out of the minimised section is the **park-time
snapshot**, kept per parked window for exactly this (at most 12, in the runtime
dir; gone when the window leaves `special:minimized` any other way, and on shell
restart). The real window is moved back *first*, underneath the expanding
picture, and the picture's last frames crossfade into it — the end state is the
live window, not the snapshot. A window parked before the feature was on (or
whose snapshot was evicted) restores plainly, as before. Off in
**Prefs → FEATURES → genie · restore** — snapshots are then not kept at all.

Exceptions and notes:

- Fullscreen windows, picture-in-picture and XWayland popups get no bar.
- **Telegram** draws its own headerbar under the bar (its settings live in a binary
  store — there is no config file to flip). Turn on **Use system window frame** once
  (Settings → Advanced, under System integration on some versions) and restart it:
  its own controls disappear and only the bar remains.
- **VS Code** draws its own titlebar and ignores both layers. Its buttons stay its own —
  or set `"window.titleBarStyle": "native"` and remove `Code` from the own-buttons
  list in `rules.lua`, then the bar above takes over.
- **Qt apps** need nothing: qtengine/Darkly style widgets, not decorations (no Qt setting
  carries a button layout — nothing to fake), and their windows are server-side here, so
  hyprbars draws their buttons.
- **hyprpm is its own package** now (it used to ship inside `hyprland`). `install.sh`
  installs it when missing and prints a loud warning if it still cannot be found —
  without it the plugin step is skipped and the bars never appear. Note `--links` does
  not run the plugin step: after a fresh clone, run the full install once (or the hyprpm
  commands by hand), not just `--links`.
- **After a Hyprland upgrade** the plugin is built against the old version and quietly
  stops loading: `hyprpm update`, then `hyprpm reload` or relog.
- No bar on a GTK app is normal — it has its own buttons. A bar *and* native buttons on the
  same window means the app is missing from the own-buttons list: find its class with
  `hyprctl activewindow` (or `hyprctl clients`) and add one line to `ownButtons` in
  `rules.lua` — the bar goes away and the app's own maximise starts working.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Features</h2>

Every feature below has its own switch in **Prefs → FEATURES** (Super+I). Off means
off — the surface does not render and the behaviour does not run. Visual features
default on; the one behaviour change, essential-only notifications, defaults off.

**Reactive glyph edges** *(FEATURES → reactive edges; also needs the edges master
switch in Prefs → SHELL)*. The glyph's edge strips gain standing jobs. While music
plays, the right strip is a VU meter fed by the same cava process the home Glyph
Matrix uses (one process, shared — the strips never start a second one); the
volume/brightness/mic flash takes the strip while it is up and the meter returns
when it fades. The bottom strip fills with the battery percentage while charging.
Priority on the bottom strip: a task's progress, then the focus drain, then
charging. Red stays where it always was — essential notifications and the mic
flash; nothing new turns red.

**Exposé** *(FEATURES → exposé)*. `Super` + `` ` `` tiles every window on the
current desktop as cards — icon, title, app, real size — in the desktops
overview's chrome, settling in with a stagger. Click or arrows + Enter focuses
the window; right-click closes the window; `Escape` closes the exposé. Like the
overview, there are no live thumbnails (toplevel capture of inactive windows is
the unreliable case in Quickshell 0.3); the card is the same information in the
shell's line language.

**Lock screen media + summary** *(FEATURES → lock media)*. The session lock gains
the player — dotted cover, title, play/pause/skip — and, under the notification
count, the newest two notification summaries. **Session lock only**: the greeter
shares the same face but has no session behind it, so its face is unchanged. The
summaries ride the shell's state file, the channel the lock process already reads
the unread count through.

**Essential notifications** *(FEATURES → essential only + the app picker under
it)*. The shell's notification server is the hook, so this is real filtering, not
a skin: with the mode on, only picked apps' notifications raise an island tile
and the edge flash. Everything else still arrives — silently, into quick
settings' history, drawn muted. Urgency is not filtered: a critical notification
always gets its red edge and its history border, picked or not. Do-not-disturb
still silences all but critical. Matching is by the notification's desktop entry;
a notification whose app sends none is matched by name or icon against the picked
apps, and unmatched means not essential. With the mode on and **no apps picked,
nothing is essential** — that is the literal setting, and the picker says so.
Notifications that carry progress (downloads, copies) are not filtered — their
task owns the bottom strip, never a tile.

**Launcher smarts** *(FEATURES → launcher smarts)*. In apps mode the query is
understood before it is searched, and the answer sits in a strip above the
results: an arithmetic line is answered by the same `qalc` the calculator mode
uses; a conversion comes from a built-in table (length, mass, data, time, speed,
volume, temperature — **no currency**: there is no rate source to convert money
with honestly); `kill <app>` matches the app's running windows and closes them
all; and files under your home directory join the results as their own block
(`find`, depth 3, hidden folders skipped, 24 at most) and open with `xdg-open`.
The strip holds Enter until Down hands the keys to the grid — Enter on it copies
the maths/conversion result or runs the kill.

**Focus timer in the bar** *(FEATURES → focus in bar)*. The focus timer (it
already lived in the clock panel and drains the glyph's bottom edge) gets a bar
part: a ring that empties as it runs, the remaining time under it in Doto, and a
hover/click card with presets (15/25/45/60), a ±5-minute stepper and
start/pause/resume/reset. Completion still flashes the edges and raises a tile.
State is **session-scoped** — a shell restart resets the timer; that was already
true of the clock-panel timer and is unchanged.

**Theme: auto + your own times** *(Prefs → LOOK → theme)*. Light / Dark / **Auto**.
Auto is a schedule, checked every 30 seconds and once at shell start (so login
and wake-from-suspend land on the right side): light from the first time until
the second, dark otherwise; defaults 07:00 → 19:00, both editable in LOOK while
Auto is on (15-minute steps), and a span that wraps past midnight works. Picking
Light or Dark by hand — in LOOK or from quick settings — holds until you switch
back to Auto; that is what manual means. Both times equal: the schedule never
fires and the current side holds.

**Named desktops + per-desktop wallpapers** *(FEATURES → named desktops; edit in
Prefs → DESKTOPS)*. Each workspace 1–10 can carry a name — shown on the desktops
overview cards — and a wallpaper from the wallpaper folder. The wallpaper runs
through the existing wall module: switching desktop changes the path and the wave
crossfades, no second engine. Picking a file makes its screen copy in the wall
cache with the usual conversion. Unset is the default: the number and the global
wallpaper.

**Screenshot: grab text + scan QR** *(FEATURES → shot text + qr)*. Two modes join
the shot pill: **text** runs the framed region through tesseract, **qr** through
zbarimg (QR and barcodes). The decoded text goes to the clipboard and onto the
result card in place of the thumbnail; a scanned link opens on click. They read
the frozen frame the shot module already captured, so the timer does not apply.
Nothing read shows as nothing read. Packages: `tesseract`, `tesseract-data-eng`,
`zbar` (installed by `install.sh`).

**Profile picture** *(Prefs → LOOK → photo)*. The lock/greeter avatar is the dot
ring by default. Set a photo — a path field with a live preview (Quickshell 0.3
has no native file dialog; the field is the honest version) — and it is copied to
the shell's state dir and to `~/.face` (a previous `~/.face` is backed up first,
and Clear restores it). The lock shows it round-clipped inside the dot ring. The
greeter runs as its own user and cannot read your home: `./install.sh --greeter`
syncs each user's `~/.face` to `/etc/greetd/faces/<user>` (mode 644), which the
greeter tries first. No photo anywhere → the dots, as before.

**Power modes** *(quick settings, the bar's battery card, Prefs → POWER)*. Four
modes, and every one of them is wired to something real. The cpu side is
power-profiles-daemon's own profile — the same one `powerprofilesctl` drives:
**eco** is its power-saver, **balanced** is balanced, **max** is performance
(only where the hardware offers it). The shell just sets it, so
`powerprofilesctl get` always agrees with what the shell shows, and the daemon
itself remembers it across reboots. **Ultra** is eco plus a layer of the
shell's own, laid over your settings without editing them: the main screen
drops to its lowest refresh rate, animations, blur and shadows switch off —
leave ultra and your refresh rate and looks come back whole. Game mode
composes on top in the same derived way (its "keep" choices win while a game
runs; neither mode touches the other's switches). Two honest edges: if the
daemon isn't answering, Prefs → POWER says so in red instead of pretending —
the cpu profile then can't change, though ultra's screen and looks still
apply — and install.sh won't enable the daemon over **tuned** or **tlp**,
which manage the same knobs; it prints what switching over takes instead.

**Ultra on battery** *(Prefs → POWER → ultra on battery; laptops, off by
default)*. Unplug and ultra takes over by itself; plug back in and the mode
you had returns — the shell remembers it across restarts, so a reboot
mid-battery doesn't strand you. Picking a mode by hand while on battery
takes over from it: the automatic return is cancelled and your pick stands.

**Shell performance** *(Prefs → POWER → shell)*. Not the cpu — the modes
above own that, through the daemon. This is what the glyph shell itself
spends: how often it samples `/proc` for its stats, re-checks recording and
airplane state (a process spawn each time), and reads an external monitor's
brightness back over DDC (a ~300 ms `ddcutil` call each time). **Full** is
the rice as shipped (2 s / 3 s / 5 s). **Trim** runs every one of those at
half rate, and the home orb breathes at half rate with them. **Lite** runs
them at quarter rate (8 s / 12 s / 20 s) and stands the eye-candy down: the
cava visualisers (the edges' VU meter, home's matrix) stop registering, so
the cava process never starts for them; the RunCat freezes and stops asking
for cpu figures; the spinning covers stop; the orb holds still. One key,
everything derived from it — flip it and the shell re-binds live, restart
and it simply reads the key back.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Screens, colour and the small things</h2>

**Per-screen shell** *(Prefs → DISPLAY, HOME)*. Every monitor carries its own bar
on/off, home on/off, widget set and wallpaper, stored under the monitor's **model**,
not its port — the same screen through a dock or another cable keeps its settings,
and a projector in the same port doesn't inherit them. DISPLAY shows the screens as
Hyprland placed them: drag one and it docks to a neighbour's edge or centre, and the
drop is applied at once; under the map are that screen's brightness (built-in only),
logical size, scale and refresh (highest by default), and the bar/home switches.
HOME edits the widget set of the screen picked there. The wallpaper picker sets all
screens or just one; the lock shows each screen its own wallpaper. Per-desktop
names and wallpapers (Prefs → DESKTOPS) are a different axis — workspace, not
monitor — and win on their own workspace.

**Bar edge** *(Prefs → BAR → edge)*. The bar lives on the **left** edge or the
**top**. On top it is a row: workspaces run sideways, the clock gains its colon, the
battery lies down, popups drop below their parts and the calendar slides down under
the clock; the glyph island and the notification flash make room under it. The deck
stays at the bottom either way, so the genie minimise still lands in the deck's
minimised section exactly as before. The tray pool gains a **RunCat**: it runs
faster the busier the CPU is, and the CPU is only polled while the cat is in the
tray. The tray's Wi-Fi is drawn as two arcs and a dot now, with a slash when off.

**Style: where the colour comes from** *(Prefs → STYLE, or the launcher's style
tab)*. Three sources. **Nothing**: black, white, red. **Wallpaper**: up to four of
its tones, read by a colour quantiser, through a Material You variant — monochrome,
neutral, tonal spot, rainbow, content, fidelity, fruit salad, expressive, vibrant.
**Palette**: Catppuccin, Rosé Pine, Gruvbox, Nord, Dracula, Tokyo Night, Everforest,
Kanagawa and more, each with its light/dark pair where the family has one. The shell,
Hyprland's borders and kitty follow at once; GTK and Qt apps are recoloured as
copies under `~/.local/state/rice/glyph` and pick it up at their next start (the
window buttons' discs are carried into the copies, so they survive a palette).
STYLE shows a live mock desktop in whatever your cursor is over — hover previews,
Enter or click sets it. Light/dark is separate and keeps the palette: the **Auto
schedule** (Prefs → LOOK) flips the pair, never the source, and a palette with no
pair simply doesn't flip.

**Corners** *(Prefs → WINDOWS → panels)*. A 0–100 % dial scales the corner radius
of every panel, card, pill and toggle in the shell; 100 % is what it has always
been, 0 is square. Round things stay round — discs, dots and rings are not panels.
The lock screen follows it too.

**Audio settings** *(Prefs → AUDIO)*. Output and input side by side: a volume ring,
mute, and every device on the machine; click or ←→ makes one the default
(wireplumber remembers it across reboots). A duplex node appears in both lists, and
turning the mic's ring up doesn't unmute it. Lists longer than eight scroll. The
live level row is **off by default**: its monitor crashes quickshell 0.3.0, so it
only exists when you switch it on there — on quickshell 0.3.1+ it just works.

**Sounds** *(Prefs → FEATURES → sounds; volume and kinds in Prefs → AUDIO)*. The
shell has a quiet voice of its own: seven short blips, synthesized by
`tools/make_sounds.py` (no samples — sine and noise voices, lowpassed, gone in
a blink), played through Qt's SoundEffect so there is no process spawn in the
way. A pop when the launcher or quick settings open (not on the hover peek), a
tick from the volume keys and sliders — the keys are the shell's own now, like
the brightness keys, so a volume change nobody asked for stays silent — a soft
chime when a notification actually arrives (do-not-disturb and essential mode
have already decided), the shutter click on a screenshot that landed (failures
stay silent), a two-note nod when the charger goes in or out, and a down/up
pair for the lock engaging and the password being accepted. Three categories —
interface, alerts, system — each with its own switch, one volume ring, and
silence over a fullscreen game, the lock pair excepted.

**The cat tile takes your gifs**. Drop any `.gif` into `~/Pictures/Gifs` and the
home cat tile plays it — click the tile or scroll over it to flip through them,
or pick in Prefs → HOME while the cat is selected (a strip of dotted thumbnails).
Non-square gifs fit whole; no gifs there, the cat as before. The wallpaper picker
also gains a **vivid** look: the dot grid in the wallpaper's own colours, between
dots and mono on Tab.

**Wheels and other people's text**. A hi-res wheel (an MX Master sends 15 ticks a
click) steps the workspace pill, the bar's volume and the quick sliders exactly once
per notch — 5 % a notch, a touchpad a quarter of that on the sliders, and a touchpad
never scrolls the pill at all. And a security note: strings that come from other
people — Wi-Fi names, Bluetooth device names, notification titles, track names,
window titles — are rendered as **plain text** everywhere. Qt would otherwise treat
them as HTML, and a neighbour's network name containing an `<img>` tag could make
your shell fetch a URL of their choosing. Nothing in the shell looks lyrics up
online any more, either.

**Captive portals** *(VPN panel)*. If the network turns out to be a captive portal,
the tunnel and proxy Clash Verge raised behind it are taken down once and come back
by themselves when the network lets you through; turn the tunnel on by hand behind
a portal and it stays. Bluetooth does the mirror trick: devices connected when the
adapter goes off come back when it comes on (BlueZ drops the connections a moment
*before* it reports the adapter off, so the shell keeps the list as it goes).

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Gestures</h2>

Windows-style trackpad gestures, on the compositor's own engine, so the left/right
switch tracks your fingers 1:1:

| Gesture | |
|---|---|
| **3 fingers left / right** | previous / next desktop, finger-following |
| **3 fingers up** | the desktops overview: one card per desktop that has windows — its number, a map of its windows in their real layout, their titles; pick a card to go there. Also on `Super` `Tab`; `Escape` closes it, arrows + `Enter` pick |
| **3 fingers down** | show desktop: every window on this desktop parks into `special:minimized` — they wait in the deck's minimised section and restore from there |
| **4-finger tap** | quick settings |
| **5 fingers down** | sleep |

Keyboard, same family: `Super` `Tab` — the desktops overview; `Super` `` ` `` — the
exposé, every window on the current desktop as cards (Prefs → FEATURES → exposé).

The tap is the odd one out: neither Hyprland's gesture engine nor libinput has a tap
shape, so one small daemon (libinput-gestures, AUR) watches for it alone — a short
stationary 4-finger touch reads as a hold there, and the hold runs on release.
Movement cancels a hold inside libinput, so it cannot fire mid-swipe; the daemon only
reads the pad (no grab), so the native swipes are untouched, and 4 fingers have no
native binding to collide with. It needs the `input` group, which `install.sh`
already adds for ydotool. To turn gestures off: comment the `hl.gesture` lines in
`config/hypr/hyprland/gestures.lua`; for the tap, the one line in
`config/libinput-gestures.conf` (or stop starting libinput-gestures in `execs.lua`).

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Login screen (greeter)</h2>

The lock screen, at boot. The rice's session lock only exists inside a session, so the
default install still boots into sddm's plain card. The optional greeter step replaces it
with **the same face**: same dot clock, dotted avatar, password pill, same dots — one
drawing (`lock/LockFace.qml`) with its PAM backend swapped for
[ greetd ](https://git.sr.ht/~kennylevinsen/greetd) via Quickshell's Greetd service
(`greet.qml`).

```sh
~/.local/share/glyph/install.sh --greeter   # Arch only; separate on purpose, not in the default run
```

What it does, in order: installs `greetd`; copies the shell config to `/etc/greetd/glyph`
(the greeter runs as the `greeter` user and cannot read `~/.config` — re-run `--greeter`
after a pull to refresh the copy); installs the fonts system-wide in
`/usr/share/fonts/glyph` (same reason — without them the Doto clock is not Doto); writes
`/etc/greetd/config.toml`, `hyprland.lua` and `glyph-greeter` (a changed file that already
exists is backed up to `~/.dots-backup-<date>/etc/greetd/` first); and only then swaps the
display manager — the currently enabled one (sddm, gdm, …) is disabled and its name
recorded in `~/.dots-backup-<date>/previous-display-manager.txt`, greetd is enabled. If
anything fails before the swap, the old login is untouched. Re-running changes nothing
twice.

The greeter session is a **stripped Hyprland** (`config/greetd/hyprland.lua`): no plugins,
no binds, no daemons — it starts the face and exits when the face does, which is what lets
greetd hand over to your session. It is launched through `start-hyprland -- --config …`
(Hyprland's watchdog wrapper; Hyprland's own arguments go after the `--`): launching the
raw `Hyprland` binary instead makes Hyprland paint a *"started without start-hyprland"*
warning banner across the greeter screen. The wrapper does not change the hand-over — it
stays in front until Hyprland exits and exits with it on a clean exit, which is exactly
the login path. Its input section mirrors the session's, NumLock
included: `numlock_by_default` is on, so a numpad PIN types from a cold boot without
touching NumLock. Keyboard focus is held from the first frame — just start typing; keys
combined with Ctrl/Alt/Super are ignored (they are shortcuts, not password characters).

- **User switching:** the name sits in a bubble with a caret. Click it and every other
  human user on the machine (uid ≥ 1000, real shell) is listed; picking one cancels the
  in-flight auth, clears the field and starts auth for that user. Faces come from
  AccountsService (`/var/lib/AccountsService/icons/<user>`) or `~/.face`, else the dotted
  gradient. The last picked user is remembered and pre-selected next boot.
- **Session:** exactly the one you already run — the `Hyprland (uwsm-managed)` entry,
  resolved at runtime from `/usr/share/wayland-sessions/*.desktop` (fallback: the first
  Hyprland entry, then the first entry there is). There is deliberately no session picker
  on the face.
- **Honest notes:** greetd *replaces* your display manager — that is the whole point, and
  the step is separate and explicit for that reason. Weather and the player line come from
  session services; with no session yet they simply stay empty, as the lock's fallbacks
  already allow. The layout chip reads `en` until login (the stripped compositor's layout
  is the one in `hyprland.lua` — keep its `kb_layout` in step with the session's).

Rollback, as printed by the step itself:

```sh
sudo systemctl disable greetd && sudo systemctl enable sddm   # or whichever DM was recorded
```

And if the greeter ever fails to appear: Hyprland keeps VT switching alive, so
`Ctrl+Alt+F3` → log in on the text console → run the rollback → reboot.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

Either way, when PAM itself has something to say — a faillock lockout, say — the greeter shows PAM's own words
instead of a generic "denied".


<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Dependencies</h2>

| | |
|---|---|
| **Shell** | `quickshell` (Qt 6.9+) · `hyprland` 0.56+ · `hypridle` · `hyprsunset` · `xdg-desktop-portal-hyprland` · `jq` · `curl` · `python3` · `libqalculate` |
| **System** | `networkmanager` · `bluez` · `pipewire` · `pipewire-pulse` · `pipewire-alsa` · `wireplumber` · `upower` · `power-profiles-daemon` · `brightnessctl` · `libnotify` · `playerctl` · `polkit-gnome` · `gnome-keyring` · `geoclue` |
| **Capture** | `grim` · `slurp` · `imagemagick` · `libvips` · `gpu-screen-recorder` · `cliphist` · `wl-clipboard` |
| **Terminal** | `kitty` · `fish` · `starship` · `fastfetch` · `btop` · `cava` · `eza` · `zoxide` · `direnv` |
| **Look** | `papirus-icon-theme` · `adw-gtk-theme` · JetBrains Mono Nerd Font · `noto-fonts-emoji` (Emoji 17) · `noto-fonts-cjk` · Bibata · `qtengine` · `darkly` |
| **Optional** | `clash-verge-rev` · `nvidia-utils` · `ydotool` · `hyprpicker` · `swappy` · `trash-cli` |

From the AUR only `qtengine`, `darkly`, Bibata and Zen, plus Spicetify and Clash Verge if picked; all optional. The VPN panel expects Clash Verge in English.
NixOS: change the `/usr/lib` agent paths in `hypr/hyprland/execs.lua` and the Papirus path in `quickshell/rice/rice`.

<div align="center"><img src="assets/divider-dots.svg" width="720" alt=""></div>

<h2 align="center">Colours</h2>

<div align="center"><img src="assets/palette.svg" width="720" alt="Palette, dark: #000000 #0E0E0E #1A1A1A #2A2A2A #4A4A4A #8C8C8C #F2F2F2 #D71921; light: #E9E9E9 #FFFFFF #F1F1F1 #D9D9D9 #B8B8B8 #6E6E6E #0B0B0B #D71921"></div>

<br>

Dark and light. Red marks the one live thing on screen.
Fonts: Doto, Space Grotesk, Space Mono, JetBrains Mono Nerd Font.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Inspiration</h2>

- [**Nothing OS**](https://nothing.tech): the look and the Glyph lights.
- [**Doto**](https://github.com/oliverlalan/Doto): the dot matrix font.
- [**Gadgetbridge**](https://codeberg.org/Freeyourgadget/Gadgetbridge): the earbuds protocol in `glyph/ear`.
- [**Caelestia**](https://github.com/caelestia-dots/shell): the shell I used before; the deck and hardware detection follow it.

<div align="center"><img src="assets/divider-matrix.svg" width="720" alt=""></div>

<h2 align="center">Credits</h2>

**Glyph** is made by [**Nebelung-cloud**](https://github.com/Nebelung-cloud): [glyph-rice](https://github.com/Nebelung-cloud/glyph-rice)
and its sibling [Demon's Shot](https://github.com/Nebelung-cloud/demons-shot-rice). The shell, the launcher, the theme — all of it is his.
This repository is my personal fork, kept under the same GPL-3.0 license; upstream is the place to look for the project itself.

What my fork changes on top of upstream:

- launcher: tap `Super` opens it again on Hyprland 0.57, where binds on the modifier key itself stopped firing —
  the release is detected by polling the key state instead of `bindr` (`hypr/hyprland/keybinds.lua`)
- gestures: workspace swipe horizontal, 4 fingers; 3 fingers for the special workspace
- keys: `Super` `Q` closes a window, `Super` `T` opens the terminal

From the forks — a batch of this fork's work was first built in other forks of the rice and
ported here change by change; every ported commit names its author in a `Co-authored-by:` trailer:

- [**AMM021**](https://github.com/AMM021/rice_nothing): the lock screen's
  power menu, the first-login welcome card and its wallpapers, the guided installer
  (dry run, `--update`, `--uninstall`, `--fix-plasma`), drive automount, and the game-mode
  and quick-outputs ports below.
- [**Isaqdn03**](https://github.com/Isaqdn03/glyph-rice): DDC deferred refresh and the
  `--skip-ddc-checks` calls, the cava NaN guard, auto game mode, the palette following into
  tmux, Firefox (via pywalfox) and Vesktop, LocalSend, the home weather centring and section
  hides, the quick settings outputs list.
- [**SenulMapa**](https://github.com/SenulMapa/glyph-rice): the lock length-hiding idea, the
  portrait scale fix, the monitor/input guards.
- [**Dimashyt**](https://github.com/Dimashyt/glyph-rice): GPU load on Intel iGPUs.

The Vesktop theme stands on [refact0r's midnight](https://github.com/refact0r/midnight-discord)
(MIT), and the LocalSend Nautilus extension follows Omarchy's (MIT). The five welcome
wallpapers are CC0 — generated for the rice with ImageMagick.

<div align="center"><img src="assets/divider-dots.svg" width="720" alt=""></div>

<h2 align="center">License</h2>

[GPL-3.0](LICENSE). Fonts are under the [OFL](config/fonts/OFL.txt), cava shaders keep their MIT headers.
Nothing, Nothing OS and Glyph are trademarks of Nothing Technology Ltd; this is a fan project, not affiliated with Nothing.

<div align="center"><img src="assets/divider-dots.svg" width="720" alt=""></div>

<div align="center">

```
ᓚᘏᗢ  · · ·
```

```
⠀⠀⠀⠀⣰⣶⣦⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣤⣶⣶⡆⠀⠀⠀⠀
⠀⠀⠀⢠⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣶⣿⣿⣿⣿⣿⠀⠀⠀⠀
⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣿⣿⣿⣿⣿⣿⡆⠀⠀⠀
⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣄⣀⣀⣀⣀⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀
⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀
⠀⠀⠀⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁⠀⠀⠀
⠀⠀⠀⠀⢿⣿⣿⣿⣿⣿⡿⢿⣿⣿⣿⣿⣿⣿⣿⣿⠿⣿⣿⣿⣿⣿⣿⡏⠀⠀⠀⠀
⠀⠀⠀⠀⣼⣿⣿⣿⣿⡏⠀⠀⢹⣿⣿⣿⣿⣿⣿⠃⠀⠀⣿⣿⣿⣿⣿⣆⠀⠀⠀⠀
⠀⠀⠀⣸⣿⣿⣿⣿⣿⣷⣀⣀⣼⣿⣿⣿⣿⣿⣿⣦⣀⣠⣿⣿⣿⣿⣿⣿⡆⠀⠀⠀
⣀⣠⣤⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣤⣀⡀
⠻⠿⠛⣿⣿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣷⠀⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠛⠿⠇
⠀⢀⣠⣾⣿⣿⣿⣿⣿⣿⡈⢿⣿⣿⣿⠃⠸⣿⣿⣿⡿⢰⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀
⠀⢿⠿⠋⢻⣿⣿⣿⣿⣿⣷⣄⣉⣉⣡⣾⣧⣈⣉⣉⣴⣿⣿⣿⣿⣿⣿⠏⠙⢿⡗⠀
⠀⠀⠀⠀⠀⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠏⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⠁⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠛⠻⠿⢿⣿⣿⣿⣿⠿⠿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀
```

</div>
