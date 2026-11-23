# Galaga — project handover

Everything a new maintainer (human or agent) needs to work on this rice
without re-learning its lessons the hard way. Read this first; the
README covers installation and user-facing behaviour, this file covers
what the project *is*, how it is put together, and where it stands.

## 1. What this is

**Galaga** is a Nothing OS–styled desktop shell ("rice") for
**Hyprland + Quickshell**, built and used daily by its owner.

- Repo: `github.com/himanshuksr0007/Galaga` (renamed from glyph-rice on
  2026-11-11; the old URL redirects).
- Machine it runs on: Infinix INBook Y4 Max, 16″ 16:10 (single panel,
  eDP-1, 1920×1200), 13th-gen Intel i5, **CachyOS** (Arch), user
  `himanshur`.
- Versions that matter: **Hyprland 0.57.2**, **Quickshell 0.3.2** on the
  machine (development targets the 0.3.0 API). Hyprland is configured
  through its **Lua API** (`config/hypr/hyprland/*.lua`), not hyprlang.
- Lineage: `Nebelung-cloud/glyph-rice` → `yasakei/glyph-rice` → this
  fork. The local git history (284 commits) starts at the upstream
  import; everything after it is fork work. Section 6 lists the delta.
- Companion repo: a port of the **hyprdrag** plugin (by yz778) to
  Hyprland 0.57.2 lives in its own repo and is built with hyprpm; the
  shell works without it (see DragWatch, §7.2).

## 2. How work is done here (read before changing anything)

- **The owner's machine is the only real test.** A sandbox check can
  prove a file parses and loads; it cannot prove Bluetooth bonds, audio
  routes, Wayland layer behaviour or plugin loading. Ship changes with
  a clear statement of what still needs an on-machine check, and treat
  the owner's verdict (usually a screen recording) as ground truth —
  when his evidence contradicts your theory, his evidence wins.
- **Nothing fake.** A control that renders must work; a number shown
  must be measured, never estimated or invented. If a capability has
  no real backend, it does not get a row in the UI.
- **One setting, one home.** When a control moves into a new page, its
  old home is deleted in the same change.
- **User-facing strings read like a shipping OS** — no design or meta
  commentary in the UI, and shell UI strings are lowercase.
- **Commits** are authored as the owner
  (`himanshuksr0007 <83110103+himanshuksr0007@users.noreply.github.com>`),
  one concern per commit, titles that describe the change only — no
  references to plans, agents or process. Ported work carries a
  `Co-authored-by:` trailer with the original author's name and email.
- **Verification before "done"** (see §8): qmllint for syntax, then a
  real QML *engine* load of every file — a brace-balance or text check
  is not verification and has shipped load failures before.
- Git pushes use a token the owner pastes per session; nothing is
  stored. `origin` refs in a fresh clone can be stale — verify a push
  with `git ls-remote`.

## 3. Repository layout

```
install.sh                  the installer (1,565 lines, §5)
config/
  hypr/
    hyprland.lua            entry point; requires hyprland/*.lua, then ~/.config/hypr/user.lua
    hyprland/               animations, decoration, drag, env, execs, functions,
                            general, gestures, group, input, keybinds, misc,
                            rules, titlebars (all Lua)
    scripts/                altf4.sh, galaga-session.sh, minimise.sh, show-desktop.sh
  quickshell/
    galaga/                 THE SHELL (linked to ~/.config/quickshell/galaga)
      shell.qml             composition root (254 lines, §4)
      Theme.qml             theme + the persisted state adapter (galaga.json)
      Sys.qml               session services hub (audio, brightness, idle flags…)
      greet.qml / lock.qml  greetd greeter face / session lock (separate processes)
      app/                  the Settings app (21 pages) + the Task Manager
      bar/ quick/ deck/ home/ launcher/ lock/ power/ …
      services/             singletons: Snap, DragWatch, Eq, SysStats, BtAgent, …
      settings/Rules.qml    writes Hyprland-facing config (shared data file, §4)
    rice/rice               the `rice` command (shell switcher / control script)
  desktop/                  galaga-settings.desktop, galaga-taskmgr.desktop
  pipewire/                 the EQ filter-chain config
```

## 4. Architecture

### 4.1 The shell (`shell.qml`)

`ShellRoot` instantiates every surface: Launcher, Quick (quick
settings), SoundMenu, BtMenu, WifiMenu, Power, Deck, DropDeck,
Desktops, Expose, Switcher, Genie, Shot (screenshots), SnapPop,
SnapZone, Vpn, Walls, Cal, Clip (clipboard), Buds, Galaga (notification
island + edge strips), and per-screen `Variants` holding
Back/Home/Hot/Bar. Global shortcuts are `GlobalShortcut { appid:
"shell" }` components bound from `keybinds.lua` via
`hl.dsp.global("shell:<name>")`.

Two apps are **lazy**: Settings and the Task Manager live in
`LazyLoader`s, are built on first open, and are **unloaded on close** —
a closed app holds nothing, and reopening builds it fresh (Settings
always opens on its About page; deep links still land on their page).

Lazy singletons are started by reading a property in shell.qml
(`autoGame: Game.on`, `autoBtAgent: BtAgent.on`, …).

### 4.2 State

- `Theme.state` — a JsonAdapter persisted to
  `~/.local/state/rice/galaga.json`. Feature toggles, per-device EQ,
  deck sections, bar contents and snap options live here (all
  settings do, unless noted).
- `settings/Rules.qml` — persists to
  `~/.config/demonshot/rules.json`, **a data file shared with the
  demonshot rice**. Its fields must not be deleted even when Galaga
  stops reading one. Rules applies monitor/input/motion/night-light/
  idle (hypridle) configuration by generating `hl.config(...)` Lua and
  sending it through **`hyprctl eval`** — that is the working channel
  for runtime config; `hl.config` is *not* a dispatcher.
- Hyprland Lua dispatchers from QML go through
  `Hyprland.dispatch("hl.dsp.…")` strings (real dispatchers only).

### 4.3 The Lua side

`config/hypr/hyprland.lua` requires the modules in `hyprland/`, then
the user's own `~/.config/hypr/user.lua`. Notable files:

- `keybinds.lua` — all binds, including the shell globals
  (`shell:settings` on Super+I, `shell:taskmgr` on Ctrl+Shift+Esc, …).
- `rules.lua` — window rules, including the **`ownButtons`** list (§7.6).
- `titlebars.lua` — hyprbars plugin config; sets `_G.GALAGA_HYPRBARS`.
- `execs.lua` — exec-once lines, plugin loading guards.

### 4.4 The `rice` script

`config/quickshell/rice/rice` (sh): no-arg = current shell, `list`,
`start`, `restart`, `kill`, `switch <name>`, `lock`, `settings`,
`taskmgr`. The app-list entries run `rice settings` / `rice taskmgr`,
which reach the shell over `qs ipc` (`IpcHandler` targets in
shell.qml).

## 5. The installer

`install.sh` (pacman/yay, symlink-based — a `LINKS` table maps
`config/…` paths into `$HOME`; the whole galaga tree is one link, so
any file in it is live at runtime after a pull).

Modes: guided run, `--dry-run`, `--with <extras>`, `--browsers <list>`,
`--update` (pull + refresh; has a guarded reset fallback), `--links`,
`--greeter` (greetd + the Galaga face, replaces the current login),
`--quiet-boot` / `--no-quiet-boot` (§7.5), `--uninstall`.

The installer also: writes the Bluetooth policy into
`/etc/bluetooth/main.conf` (`ControllerMode=bredr`,
`FastConnectable=false`, `Privacy=off` — BLE-only peripherals are the
known trade-off), installs the session package set (including
`python-gobject`, needed by the Bluetooth agent), writes the
Cloudflare WARP autostart stub (§7.7), and asks the browser question
that Super+W later honours.

Activation cheat sheet after a change:

| Change | Activation |
|---|---|
| QML only | `git pull` + `rice restart` |
| Lua (binds/rules) | `git pull` + `hyprctl reload` (+ `rice restart` if QML too) |
| Installer / packages / desktop files | `git pull` + `./install.sh` |
| Plugin (hyprdrag) | hyprpm update + reload |


## 6. Feature list

Everything below exists and is wired; items marked ◦ are gated by a
feature toggle in Settings → Features.

### Upstream glyph-rice vs Galaga (the delta)

Upstream `glyph-rice` (Nebelung-cloud, via the yasakei fork) provided
the foundation: the Nothing OS visual identity and theme system, the
Quickshell shell skeleton (bar, home screen, lock face, launcher
basics), the Lua config layout, the symlink installer skeleton, and
the `rice` shell switcher. It was a themed shell; window management,
settings and system integration were essentially Hyprland defaults.

**Galaga is that skeleton grown into a full desktop environment.**
Of the 284 commits in this repo, the first is the upstream import;
everything else is fork work, including: the rename to Galaga (repo,
shell directory, state file, desktop entries); the entire **Snap**
window-management layer; **Deck + DropDeck**; **Genie**; the
**Switcher / Exposé / Desktops** views; the **Quick panel + Picker**
and the sound/Bluetooth/Wi-Fi bar menus; the 21-page **Settings
app** and the **Task Manager**; the **EQ system** and per-app mixer;
the **Bluetooth pairing agent** and the unified connect flow;
**quiet boot**; the **clipboard** with pins; the **screenshot
editor**; the hyprbars **mac-disc titlebars** and the ownButtons
system; Windows-style **Alt+F4**; 4-finger gestures; the
**hyprdrag port** to Hyprland 0.57.2; the greetd **greeter** wearing
the lock face; and a full performance/dead-code audit. In short:
if it opens, snaps, pairs, plays, locks or configures, it was added
here.

### Shell surfaces
- **Bar** — floating pill (top or bottom), window title, tray, clock;
  the compositor reservation is the 78-unit strip only.
- **Home** — per-screen home screen: clock, weather, bento widgets.
- **Launcher** — apps, windows, files, run; DesktopEntries icons.
- **Quick settings** — right-edge hover or Super+A: tiles (Wi-Fi,
  Bluetooth, airplane, night light, caffeine…), sliders, and the
  **Picker**: the Wi-Fi/Bluetooth device list under the tiles. The
  Picker's tap logic is the reference implementation for device
  connect behaviour (§7.3).
- **Sound / Bluetooth / Wi-Fi menus** — bar dropdowns mirroring the
  Quick panel's manners, with deep links into the Settings app.
- **Deck** — bottom-edge dashboard (150 ms dwell): clock, weather,
  system stats, per-core CPU, network history, media, and the
  minimised-windows section. Sections are user-ordered
  (`Theme.state.deck`).
- **DropDeck** — while dragging a window, a bottom strip of workspace
  chips; dropping moves the window and arranges the target workspace.
- **Desktops / Exposé / Switcher** — workspace overview, all-windows
  view of the current desktop, and an MRU Alt+Tab switcher (no live
  thumbnails, by design).
- **Power menu**, **Calendar**, **VPN panel**, **Wallpaper picker**,
  **Charms** (emoji/symbol picker), **Welcome** card (first login).
- **Notification island + Galaga edge strips** — notifications,
  volume/brightness/progress strips, battery-critical flash. Power
  *connection* changes notify by tile only; the red strip flash is
  reserved for battery-critical.
- **Lock screen + greetd greeter** — one shared face (`lock/LockFace`)
  for the session lock and the boot login.

### Window management
- **Snap** (§7.1) — zones, groups, linked resize, snap assist popup,
  drag-to-zone, arrange-on-open, drop-arrange. Settings → Windows
  toggles gate each part.
- **Genie** ◦ — minimise warps the window into the deck's minimised
  section; restore expands the park-time snapshot back out. (A true
  live-window *reverse* warp is a known future thread, not built.)
- **mac-style titlebar discs** via the hyprbars plugin (close /
  minimise / fullscreen), with per-window titlebar clearance in Snap.
- **Alt+F4** the Windows way: closes the focused window; on the
  desktop it opens the power menu (`config/hypr/scripts/altf4.sh`).
- **Gestures** — 4-finger swipe: overview and workspace switching.
- **Minimise** parks to `special:minimized` (`minimise.sh` is the one
  entry point); Super+Alt+M works for every window, including apps
  whose own minimise button Hyprland drops.

### Apps (in the app list)
- **Galaga Settings** — a 21-page macOS-shaped settings app (§7.4):
  About, General, Sound, Notifications, Lock, Appearance,
  Desktop & Deck, Displays, Windows, Wi-Fi, Bluetooth, Network, VPN,
  Battery, Mouse & Touchpad, Keyboard, Features, Users, Apps,
  Storage, Software Update. Every control has a real backend.
- **Task Manager** (§7.7) — Processes / Performance / Startup,
  Ctrl+Shift+Esc, `rice taskmgr`.

### Audio
- **System EQ** — a PipeWire filter-chain sink (`galaga-eq`) with
  per-device EQ memory; `services/Eq.qml` owns engagement (§7.3).
- **Per-app volume mixer** in the sound menu (streams listed from
  registry facts only — see the binding trap, §8).
- **Bluetooth audio auto-switch**: a BT sink appearing becomes the
  output (through `Eq.pick`); vanishing returns to the home sink.
- Exactly one output is ever the output — no dual output, by the
  owner's decision.
- UI sounds throughout (Sounds service), quiet while a game is
  fullscreen.

### Bluetooth
- Menus + Settings page (adapter info via bluetoothctl, reset,
  service restart via pkexec, remove-all).
- **The shell runs its own pairing agent** (§7.3) — without it, no
  bond from the UI completes at all.
- Adapter policy in `/etc/bluetooth/main.conf` (see §5).

### System
- **Quiet boot** (§7.5) — silent boot into the greeter.
- **Clipboard** — history capped at 100, real pins that keep their
  own copy, a working paste button; survives relog.
- **Screenshots** — capture plus a full annotation **Editor**
  (Super+Shift+E entry).
- **Idle / auto-lock** — hypridle config generated by Rules from
  Settings → Lock (lock after / screen off after) and Settings →
  Battery (sleep); 0 = never; caffeine toggle in Quick + Battery.
- **Night light** (hyprsunset) in Settings → Displays.
- **Game mode** — a fullscreen game raises DND and quiets sounds.
- **Power profiles** — real modes incl. battery saver (the deepest
  tier; the persisted key is still called `ultra` for compatibility).
- **Software Update** page checks the system *and* Galaga's own
  commits.
- **Weather** service, **RunCat** tray CPU cat.

### Removed at the owner's order (do not re-add unasked)
- Shake-to-minimise and hot corners (removed 2026-11-19, commits
  `7de443d`, `c260897`) — services, toggles and shell wiring deleted
  completely; their retests are moot.

## 7. How the important mechanisms work

### 7.1 Snap (`services/Snap.qml`, ~1,300 lines)

Zones are fractions of the focused monitor's workarea; snapped
windows float with exact geometry; `preSnap` restores prior state.
`place(addr, rect, zone, preOver)` is the **one** placement entry.

- **Titlebar clearance**: `placedRect()` shifts a zone rect down 32
  when the window carries the hyprbars bar (`hasBar(class)`), the bar
  is on top, and the zone touches the top without being MAX.
- **Grouping**: two tests — `shareV` (x-adjacency + bottom-edge
  alignment + span overlap) and `shareH` (y-adjacency + left/right
  alignment + overlap), with `edgeTol = 26` because kitty sizes in
  whole cells and lands up to ~a line height off its assigned rect.
- **Arrange-on-open**: event-driven adoption (Hyprland raw events +
  400 ms debounce, 60 s backstop). New windows ≤ 3 s old join the
  workspace's set: 2 → side by side, 3 → one full side + two stacked
  (`trioZones`; three-across is a manual Super+Z choice only), 4 →
  grid. A fresh tiled window ≥ 50 % covered by snapped windows is
  floated and focused (`openRaise`).
- **Fill**: dragging one grouped window resizes its partner to the
  pair's true geometric union.
- Records and groups are runtime state — a shell restart wipes them.

### 7.2 DragWatch + hyprdrag (`services/DragWatch.qml`)

Drag state comes from the hyprdrag plugin's socket2 events
(`hyprdrag-movestart/movestop/…motion` with geometry). The plugin is
a fork ported to Hyprland 0.57.2 (separate repo, hyprpm). Without it,
a two-sample fallback (`mayOpen`) decides whether the pointer is
dragging, so panels don't open mid-drag; DropDeck does not exist in
the fallback world. A 15 s presence check notices the plugin
vanishing mid-session and unlatches cleanly. Drag-time FX suspension
(blur/shadows off while dragging) is applied via `hyprctl eval`.

DropDeck's hit-testing is the shell's own arithmetic (the strip is a
click-through overlay): cells re-register their global rects on
**every** cursor sample while the strip is up — on the strip's first
rise of a session its window geometry lands late, and one-shot
registration left the first drag of every session undroppable.

### 7.3 Audio and Bluetooth contracts

**PipeWire binding trap (load-bearing):** in Quickshell,
`PwNode.audio` exists only on nodes bound through a PwObjectTracker.
Filters over `Pipewire.nodes.values` must use registry facts only
(`isStream`, `isSink`, `properties`) — never `.audio` — or the list
silently empties (this bug hid the whole apps mixer once).

**EQ** (`services/Eq.qml`): `pick(dev)` is the only entry point. If
the chain is alive and the device's stored EQ is on, the chain
engages: link pairs are planned and verified from `pw-dump`, and the
chain becomes the default sink. Otherwise the chain steps aside and
the device is the plain default. A fail-safe disengages on any
verification miss. **Known bug, knowingly shipped:** after a PipeWire
restart the chain node vanishes, `feedFor` is cleared, WirePlumber
restores `galaga-eq` as default, and the dead chain can sit as the
default sink until EQ is toggled off→on for that device. The owner
ordered a previous fix series reverted (2026-11-17); do not re-apply
that approach unasked.

**Bluetooth pairing**: Quickshell's Bluetooth module registers **no
pairing agent** (true of the 0.3.0 sources), and BlueZ completes no
bond without an agent somewhere — UI connections were hollow radio
links until the shell grew one: `bt-agent.py` (Python/Gio) registers
`org.bluez.Agent1` at `/org/galaga/BtAgent`, capability
`NoInputNoOutput`, accepts just-works requests, asks to be the
default agent, and re-registers if bluetoothd restarts.
`services/BtAgent.qml` supervises it (3 s backoff). It needs
`python-gobject` (installer). Limit: devices that need a typed or
spoken passkey cannot pair through a NoInputNoOutput agent.

**Device taps everywhere follow the Quick Picker's flow exactly**:
pairing in flight → cancel; unpaired → `trusted = true` then
`connect()` alone (BlueZ bonds inside the connect, the agent
completes it); paired → plain connect/disconnect toggle. A
`pair()`-first-then-connect-on-pairing-end flow was tried in the
menu and Settings page and failed on the machine (connected, dropped
within seconds, bond lost) — do not reintroduce it.

### 7.4 The Settings app lifecycle

Settings and the Task Manager are FloatingWindows in `app/`, hosted
by LazyLoaders in shell.qml. Closing calls the window's `close()`
(hide + `closeRequested`), the loader unloads the app, and the next
open builds it fresh. A compositor close (Alt+F4) reaches the same
path via the window's `closed` signal. Pages are sibling files with
an `active` property; pages fetch their data on first visit /
activation, not at build. Widgets: the `Set*` family in `app/`
(SetHead, SetCard, SetRow, SetPick, SetToggle, SetButton, SetSlider).

### 7.5 Quiet boot

`./install.sh --quiet-boot` installs `/usr/local/bin/galaga-session`,
a wrapper session that starts Hyprland with the splash suppressed
and the plugin guard in place; `--no-quiet-boot` undoes it. Verified
working on the machine (2026-11-15). The kernel-cmdline layer of the
original design never applied on this machine ("bootloader layout
not recognized") and was not chased.

### 7.6 Window buttons and the ownButtons list

Apps that draw their own buttons (GTK headerbars, Electron, Firefox…)
get **no hyprbars bar** and are exempt from maximise suppression.
The list is curated by hand in `config/hypr/hyprland/rules.lua`
(`ownButtons`), and **mirrored** as anchored regexes in
`services/Snap.qml` — the two must be kept in step; a script diff of
the sets is the cheap check. Details that have bitten:

- Class matching is **case-sensitive**. VS Code appears twice on
  purpose: `code` (repo build) and `Code` (Microsoft build).
- The two rules built from the list (suppression vs no_bar) construct
  their patterns **separately** on purpose — sharing one joined
  pattern once made no_bar silently stop matching.
- Find a class with `hyprctl activewindow`.

### 7.7 Task Manager data

- **Processes**: `ps` polled every 2 s, only while the page is open.
  CPU% is computed from cumulative-time deltas between snapshots.
  Grouping root = the highest ancestor **below** the session
  infrastructure (boundary: `systemd`, `hyprland`, `dbus-daemon`,
  `uwsm`, `init`, or a parent pid of 1) — walking all the way to the
  user manager collapses every app into one group. End task = SIGTERM
  children-first; a group still alive next snapshot offers force
  kill. The shell's own group (quickshell/qs) and pid 1 are
  protected.
- **Performance**: fed by `services/SysStats.qml`, which samples only
  on demand. Demand is composed through flags on the `Sys` singleton
  (`Sys.deckOpen`, `Sys.taskMgrOpen`) into the one binding in
  `home/Home.qml` that owns `SysStats.detailed` — never bind
  `detailed` from two places.
- **Startup**: the merged XDG autostart view (user file wins per
  basename; Name/Icon fall back to the system file when the user file
  is a bare `Hidden=true` stub — the installer's own WARP stub is
  exactly that, and Cloudflare WARP must still list by name) plus
  systemd **user** services (enabled/masked/user-file units).
  Toggles use the standard semantics: stub write/removal for system
  entries, in-place `Hidden` edit for user-only entries,
  `systemctl --user enable/disable` (unmask first when enabling a
  masked unit), never `--now`.

### 7.8 The deck's edge gate

The deck's bottom strip hides only over a **true fullscreen** window
(state 2, via the live Wayland toplevel handle) — Hyprland's
workspace `hasFullscreen` also counts *maximized* (state 1), and
gating on it silenced the deck over every maximized window. In true
fullscreen the strip's layer is not drawn at all; Super+Space opens
the deck directly in the Overlay layer there.


## 8. QML pitfalls that have actually bitten here

Verification method first: **qmllint catches syntax only.** The
decisive check is loading every `.qml` in a real QQmlEngine with
stub modules for Quickshell (whose types the engine cannot resolve
offline) — files that pass a text check have failed on the real
shell. After any QML change: qmllint over the tree (grep `[syntax]`
→ 0), then an engine load sweep (→ 0 failures), then the audits
below. The current tree sweeps **115 files, 0 failures**.

- **Qt's V4 JS engine has no logical assignment operators** —
  `??=`, `||=`, `&&=` are syntax errors (`?.` and `??` are fine).
  One stray `??=` once cascaded to 106/109 load failures because the
  services module would not load.
- **`Singleton` root type comes from `import Quickshell`** (the
  module itself). A pragma-Singleton file importing only submodules
  fails on the real shell with "Singleton is not a type" and poisons
  every importer. Audit: every `^Singleton {` file needs a bare
  `^import Quickshell$` line.
- **`Process`, `FileView`, `IpcHandler` live in `Quickshell.Io`.**
  Same audit: every file using one needs a bare
  `^import Quickshell.Io$` line. The engine sweep *cannot* catch a
  missing one (its stubs register the types too broadly) — this exact
  miss killed the shell on first load once (Power.qml's IpcHandler).
- **An inline `component` cannot declare a signal the file root also
  declares** ("Duplicate signal name" is a real error). Pattern:
  inline components call the root's signal directly; consumers wire
  with `Connections { target: …; function onX(…) {} }`.
- **`PwNode.audio` is null until the node is bound** (§7.3). Never
  filter the PipeWire registry on `.audio`.
- **`lastIpcObject` on a Hyprland toplevel is a snapshot** from the
  last `j/clients` fetch; it does not track moves or state changes.
  Use the typed properties (`workspace`, `activated`…) and the live
  Wayland handle (`toplevel.wayland.fullscreen`…) for anything live.
- **`Process.exec()` stops a running process before starting** — the
  pattern for re-runs is a `running` guard, not blind re-triggering.
- **QML bindings are pull-evaluated**: a binding re-evaluates when a
  dependency changes, not on a timer. Shared demand flags are
  composed through the `Sys` singleton (§7.7), never double-bound.
- **Hyprland addresses**: Quickshell toplevel `address` values are
  bare hex; `hyprctl clients` JSON carries `0x`. Convert at the
  boundary.
- **Layer-shell + fullscreen**: Top-layer surfaces are not drawn over
  a true-fullscreen window; surfaces that must work there are created
  directly in Overlay (§7.8).

## 9. Current state (2026-11-23)

Remote `main` = the commit adding this file. Everything below is
pushed; the owner's machine syncs by pull (plain pulls fast-forward).

**Confirmed working on the machine** (owner-verified): quiet boot,
clipboard + pins across relog, genie minimise, 4-finger gestures,
arrange-on-open (incl. the 1+2 trio), linked resize, bar strip
reservation + maximised hug, Alt+F4's three cases, DropDeck drops
**and** its first-drag-of-session fix, Bluetooth *pairing* via the
shell's agent, and the performance/dead-code audit (Super+W honours
the installer browser pick).

**Awaiting the owner's on-machine verdict** (do not re-offer
unprompted; he works through them at his pace):
- Bluetooth connect stability on the Picker flow everywhere
  (bar menu + Settings page, commit `9d7f4c5`): forget the buds →
  tap in the bar menu → must bond, connect, stay connected, and stay
  paired after disconnect. If the bond still breaks, the next step
  is a bluetooth journal from one pair cycle, not another code
  change.
- Deck over maximized windows (`ca5bdf1`): bottom-edge hover must
  raise the deck over a maximized window; over a true-fullscreen
  video it stays silent by design.
- Task Manager (`51d36d1`): first real run — the live
  `systemctl --user` startup list and grouping against the real
  process tree are unprovable off-machine; the sidebar's "startup"
  glyph (F14DE) needs a glance in the bundled icon font.
- The Settings → Lock auto-lock section (`9cef622`).
- VS Code's titlebar (`0e1fe78`): after pull + reload + restart,
  VS Code must open with no hyprbars bar. If one survives, the class
  from `hyprctl activewindow` settles what his build reports.
- A backlog of smaller retests from the November feature batches
  (mixer feel, screenshot editor entry, BT audio auto-switch, tray
  hitboxes, Software Update's Galaga leg, pkexec flows in Settings).

**Known open issues**:
- **EQ restart-strand** (§7.3): present and knowingly accepted.
- **WARP window resurrection**: warp-taskbar can reappear after
  updates; the installer masks it only when the warp extra is ticked
  in that run, and `--update` does not run that step. A patch exists
  in the owner's history of decisions — do not re-offer it unasked.
- **Fan control is unsolved**: the EC owns the fan on this board
  (EM_IDL325_200B, Emdoor); `fan1_input` is readable, there are no
  PWM nodes and no platform_profile, and nbfc-linux has no Infinix
  config. Next step would be EC register probing — owner-gated.
- **Genie restore** (true live reverse warp) — flagged "work on
  later", unscoped.
- An unanswered diagnostic from 2026-11-16: a one-off
  "Switcher is not a type" load error on the machine, never
  reproduced; leading theory is a file-watcher race during a pull.
- Telegram's window class for ownButtons was never confirmed by the
  owner — do not add it unasked. The minimise disc for own-buttons
  apps (visual-only vs absent) is likewise his open decision.

## 10. Useful commands

```sh
git pull && rice restart              # QML changes
git pull && hyprctl reload            # Lua changes
./install.sh                          # installer/package/desktop changes
qs -p ~/.config/quickshell/galaga     # run the shell in the foreground (debug)
hyprctl activewindow                  # a window's class, for ownButtons
hyprctl clients                       # all windows, classes, fullscreen states
journalctl -b -u bluetooth            # bluetoothd's side of a pairing story
```

---

*This document describes the project as of 2026-11-23. When a section
and the code disagree, the code is right and this file wants a patch.*
