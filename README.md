<div align="center">

<img src="assets/title.svg" width="760" alt="Glyph: a Nothing OS rice for Hyprland + Quickshell">

Fork of [glyph-rice](https://github.com/Nebelung-cloud/glyph-rice) (check [Credits](#credits))

<br>

![Glyph desktop](screenshots/desktop.jpg)

**Home.** The dot clock, the greeting, and a bento of live widgets — weather, CPU, RAM,
the player, system stats — all drawn in dots. The bar rides the top edge (left works too):
workspaces, clock, tray, battery.

![Glyph desktop, light](screenshots/home-light.jpg)

**Home, in light.** The same dots, inverted — by hand, or on a schedule (Prefs → LOOK).

</div>

<div align="center"><img src="assets/divider-dots.svg" width="720" alt=""></div>

<h2 align="center">The tour</h2>

![Calendar and focus timer](screenshots/calendar.jpg)

**Cal.** Click the clock: a calendar and the focus timer — 15 / 25 / 45 / 60, a ring that
drains as it runs, in the bar too.

![The deck](screenshots/deck.jpg)

**Deck** (`Super` `Space`, or the bottom edge). Every section live: clock, weather and
forecast, CPU / memory / GPU rings with the process table and a per-core grid, network
rates, the player — and, last, the minimised section your parked windows wait in.

![Genie minimise and restore](screenshots/genie.gif)

**Genie.** Minimise is not real in Hyprland, so the rice fakes it beautifully: the white
title-bar button (or `Super` `Alt` `M`) parks the window on a hidden workspace, and the
shell warps a snapshot of it — macOS magic-lamp style, neck at the deck — into the deck's
minimised section. Click the parked row and the snapshot expands back over the live
window. Every park path runs one entry point, `hypr/scripts/minimise.sh`; if the shell
is down, the park is a plain park. Off, per piece, in Prefs → FEATURES.

![Quick settings](screenshots/quick.jpg)

**Quick** (`Super` `A`, or the bar's toggles). Wi-Fi and Bluetooth pills, the mode
toggles, brightness and volume, the power modes — and the player, with the track that
is actually playing.

![Launcher](screenshots/launcher.jpg)

**Launcher** (`Super`). Apps, run, windows, calculator, styles and tray in one search —
and the query is understood first: maths is answered, units converted, `kill <app>`
closes that app's windows, files from home join the results.

| | |
|:---:|:---:|
| ![Desktops overview](screenshots/desktops.jpg) **Desktops** — every occupied desktop as a card, its windows mapped; pick one to go there (`Super` `Tab`, 4-finger swipe up) | ![Clipboard history](screenshots/clip.jpg) **Clip** — clipboard history with dotted previews (`Super` `V`) |

![Lock screen](screenshots/lock.jpg)

*(A photo of the screen, clicked on a phone and edited by Gemini to remove the
glare — the lock cannot screenshot itself.)*

**Lock** (`Super` `L`). The dot clock over your wallpaper, the player on the face —
title, cover, play / skip — your photo in the dot ring if you set one, the password
pill, and power at the corner: sleep, reboot, power off on F10 / F11 / F12 (the
destructive two arm on the first press). The boot greeter wears the same face.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Bar menus</h2>

The tray icons open their own menus — no external applets, everything is the shell.

| | |
|:---:|:---:|
| ![Wi-Fi menu](screenshots/menu-wifi.jpg) **Wi-Fi** — networks, personal hotspot, join hidden | ![Bluetooth menu](screenshots/menu-bluetooth.jpg) **Bluetooth** — paired and new devices, battery where reported |
| ![Sound menu](screenshots/menu-sound.jpg) **Sound** — the dotted volume slider, every output | ![Sound device page](screenshots/sound-device.jpg) **A device's page** — its own volume, codec, battery; the system EQ rides along |

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Device settings</h2>

Each menu's settings button opens its full page — the menus are for the quick reach,
these are for everything else.

![Wi-Fi settings](screenshots/devices-wifi.jpg)

**Wi-Fi.** Hotspot name and password, known and other networks, the card's facts
(driver, IP, MAC), restart Wi-Fi or NetworkManager, forget everything saved.

![Bluetooth settings](screenshots/devices-bluetooth.jpg)

**Bluetooth.** Connect / forget per device, discoverable, the adapter's facts, reset
the adapter, restart the service, remove all devices.

![Sound settings](screenshots/devices-sound.jpg)

**Sound.** Master volume and mute, every output with its own page a click away.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Settings</h2>

Prefs (`Super` `I`) is one window with a page per part of the rice — everything
below is live: change it and the shell follows, no restart, no config files.

| | |
|:---:|:---:|
| ![Prefs home](screenshots/prefs-home.jpg) **HOME** — the home screen's bento: which cells, how big | ![Prefs bar](screenshots/prefs-bar.jpg) **BAR** — the tray's parts and their order, the edge it rides |
| ![Prefs style](screenshots/prefs-style.jpg) **STYLE** — colour from Nothing, the wallpaper, or a palette; light / dark / auto | ![Prefs audio](screenshots/prefs-audio.jpg) **AUDIO** — every output and input, sound kinds, the system EQ |
| ![Prefs features](screenshots/prefs-features.jpg) **FEATURES** — one switch per feature; off is fully off | ![Prefs desktops](screenshots/prefs-desktops.jpg) **DESKTOPS** — a name and a wallpaper per workspace |

![A window in the rice](screenshots/window.jpg)

**Windows.** Every window gets the same three discs, top-left — close (red), minimise
(white), maximise (black); glyphs appear on hover, unfocused discs go grey, the title
sits centred in Doto. Apps that draw their own buttons (GTK, Firefox, Zen) keep theirs.

<div align="center"><img src="assets/divider-matrix.svg" width="720" alt=""></div>

<h2 align="center">What's inside</h2>

| | | |
|---|---|:---:|
| **Bar** | launcher, workspaces, clock, tray | |
| **Home** | clock, greeting, widgets (cava as a round Glyph Matrix), dot grid | |
| **Glyph** | screen edges as OSD: volume, brightness, mic mute, notifications, progress | |
| **Launcher** | apps, commands, windows, calculator, conversions, files, tray apps | `Super` |
| **Quick** | quick settings, game mode, media, notifications | `Super` `A` |
| **Deck** | dashboard from the bottom edge | `Super` `Space` |
| **Desktops** | overview of every desktop that has windows | `Super` `Tab` / 4-finger swipe up |
| **Exposé** | every window on this desktop, as cards | `Super` `` ` `` |
| **Prefs** | settings, bar and home layout | `Super` `I` |
| **Shot** | screenshots, editor, recording, grab-text and QR modes | `Print` |
| **Clip** | clipboard history | `Super` `V` |
| **Share** | clipboard to the LAN via LocalSend | `Super` `Ctrl` `S` |
| **Charms** | emoji, kaomoji, symbols | `Super` `.` |
| **Walls** | wallpapers as dots — or vivid, in their own colours | `Super` `Shift` `W` |
| **VPN** | Clash Verge panel | `Super` `P` |
| **Cal** | calendar, focus timer | click the clock |
| **Buds** | Nothing / CMF earbuds: battery, ANC | |
| **Power** | power menu | `Super` `Esc` |
| **Lock** | lock screen — media, notification peek, power (F10 / F11 / F12) | `Super` `L` |
| **Greeter** | boot login: the lock's face on greetd | `install.sh --greeter` |
| **Rice** | shell switcher, if Demon's Shot is installed too | `rice switch <name>` |


<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Install</h2>

```sh
git clone https://github.com/himanshuksr0007/glyph-rice ~/.local/share/glyph
~/.local/share/glyph/install.sh
```

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Features, briefly</h2>

Every feature has its own switch in **Prefs → FEATURES**. Off means off — the surface
does not render and the behaviour does not run.

- **Reactive glyph edges** — while music plays the right edge strip is a VU meter (the
  home matrix's cava, shared); the bottom strip fills with the battery while charging.
- **Exposé** — `Super` + `` ` `` tiles this desktop's windows as cards; click focuses,
  right-click closes.
- **Lock media + summary** — the session lock carries the player and the newest two
  notification summaries. The greeter shares the face but has no session, so its face
  stays plain.
- **Essential notifications** — only picked apps raise a tile and the edge flash; the
  rest arrive silently into history. Critical always gets through.
- **Launcher smarts** — the query is understood first: `qalc` answers maths, a built-in
  table converts units (no currency — no honest rate source), `kill <app>` closes an
  app's windows, files from home join the results.
- **Focus timer in the bar** — the clock panel's timer as a bar ring with presets.
- **Theme auto** — light / dark on your own schedule (Prefs → LOOK; defaults
  07:00 → 19:00), or by hand from STYLE and quick settings.
- **Named desktops** — a name and a wallpaper per workspace (Prefs → DESKTOPS), shown
  on the overview cards, crossfading on switch.
- **Shot text + QR** — two more shot modes: OCR a region to the clipboard, scan a QR
  or barcode into a link (tesseract, zbar).
- **Profile picture** — Prefs → LOOK → photo: a path field with a live preview (the
  toolkit has no file dialog; the field is the honest version). The lock shows it
  round-clipped inside the dot ring; `./install.sh --greeter` syncs it to the boot face.
- **Power modes** — eco / balanced / max are power-profiles-daemon's own profiles
  (`powerprofilesctl get` always agrees); **ultra** adds the shell's layer: lowest
  refresh rate, animations, blur and shadows off. Ultra can also take over by itself
  on battery (Prefs → POWER, off by default). install.sh won't enable the daemon over
  tuned or tlp — it prints what switching takes.
- **Shell performance** — Prefs → POWER: how hard the shell itself samples stats,
  state and DDC (full / trim / lite — lite also stands the visualisers down).
- **Power from the lock** — sleep, reboot, power off on the lock face, as chips with
  their keys (F10 / F11 / F12); the destructive two arm on the first press.
- **Sounds** — the shell's own quiet voice, synthesized (no samples): panel pops,
  volume ticks, a notification chime, the screenshot shutter, charger notes, the
  lock pair. Kinds and volume in Prefs → AUDIO.

**The small things.** Per-screen shell (Prefs → DISPLAY): every monitor carries its
own bar, home, widgets and wallpaper, keyed by the monitor's *model*, so a dock or a
different cable changes nothing. Corners: one dial (Prefs → WINDOWS) scales every
panel's radius. A hi-res wheel steps exactly once per notch everywhere. The home cat
tile plays any gif dropped into `~/Pictures/Gifs`. And other people's text — Wi-Fi
names, device names, notification titles, track names — renders as plain text
everywhere: Qt would otherwise treat it as HTML, and a neighbour's network name
could make your shell fetch a URL of their choosing.

<div align="center"><img src="assets/divider-glyph.svg" width="720" alt=""></div>

<h2 align="center">Gestures</h2>

Windows-style, on the compositor's own engine — left/right tracks your fingers 1:1:

| Gesture | |
|---|---|
| **4 fingers left / right** | previous / next desktop, finger-following |
| **4 fingers down** | show desktop: every window parks into the deck's minimised section |
| **4 fingers up** | the desktops overview — one card per occupied desktop, its windows mapped in their real layout; pick a card to go there. Also `Super` `Tab` |


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
