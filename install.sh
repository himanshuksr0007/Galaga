#!/usr/bin/env bash
# Glyph: installs everything on a clean Arch and links the configs from this repo.
#   ./install.sh                   packages + services + symlinks; asks which EXTRA to install too
#   ./install.sh --with telegram   same without the question (--with "" -- just the rice itself)
#   ./install.sh --links           symlinks only (on an already configured system)
#   ./install.sh --greeter         boot login: greetd with the glyph face -- REPLACES the current
#                                  display manager (sddm/...); separate on purpose, prints its rollback
set -euo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/.dots-backup-$(date +%F_%H-%M-%S)"

PACMAN=(
    # base (cmake/meson: hyprpm builds the plugins from source)
    base-devel git curl jq python cmake meson
    # session (hyprpm is its own package -- it no longer ships inside hyprland)
    hyprland hyprpm hypridle hyprsunset hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    sddm quickshell polkit-gnome gnome-keyring geoclue upower xdg-user-dirs
    # audio, network, bluetooth
    pipewire pipewire-pulse pipewire-alsa wireplumber networkmanager bluez bluez-utils power-profiles-daemon
    # utilities called by keybinds and the shell
    brightnessctl ddcutil playerctl wl-clipboard cliphist grim slurp swappy imagemagick libvips libqalculate
    tesseract tesseract-data-eng zbar # shot: grab text (OCR) + scan QR/barcode
    gpu-screen-recorder ydotool libnotify trash-cli
    # terminal and console
    kitty fish starship fastfetch btop cava eza zoxide direnv
    # apps from variables.lua
    thunar pavucontrol
    # fonts (cjk -- kaomoji in Charms), icons (Papirus-Dark -- base for the Rice folder theme), dark base for gtk.css
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji papirus-icon-theme adw-gtk-theme
)

AUR=(
    qtengine darkly-bin bibata-cursor-theme-bin
    zen-browser-bin
    libinput-gestures # the 4-finger tap only -- the swipes are Hyprland-native (config/libinput-gestures.conf)
)

# greeter only (./install.sh --greeter). The compositor is the session's own Hyprland
# (stripped config in config/greetd/), already installed above -- greetd is the only addition
GREETER_PACMAN=(greetd)

# optional, like caelestia's optional components. What the special-workspace keybinds open -- apps in hypr/variables.lua
declare -A EXTRA=(
    [telegram]="telegram-desktop"                                        # Super+D
    [spotify]="spotify-launcher spicetify-cli spicetify-marketplace-bin" # Super+M
    [clash]="clash-verge-rev-bin"                                        # VPN panel, Super+P
    [pywalfox]="python-pywalfox"                                         # Firefox follows the palette (with the Pywalfox add-on)
)

G=config/quickshell/glyph
# repo path -> path in $HOME
LINKS=(
    "config/hypr                                .config/hypr"
    "$G                                         .config/quickshell/glyph"
    "config/quickshell/rice                     .config/quickshell/rice"
    "config/quickshell/rice/rice                .local/bin/rice"
    "config/kitty                               .config/kitty"
    "config/qtengine                            .config/qtengine"
    "$G/term/qtengine.colors                    .config/qtengine.colors"
    "$G/term/starship.toml                      .config/starship.toml"
    "$G/term/fastfetch                          .config/fastfetch"
    "$G/term/btop                               .config/btop"
    "$G/term/cava                               .config/cava"
    "$G/term/gtk-3.0/gtk.css                    .config/gtk-3.0/gtk.css"
    "$G/term/gtk-4.0/gtk.css                    .config/gtk-4.0/gtk.css"
    "$G/term/gtk-3.0/settings.ini               .config/gtk-3.0/settings.ini"
    "$G/term/gtk-4.0/settings.ini               .config/gtk-4.0/settings.ini"
    "$G/term/window-buttons                     .config/gtk-3.0/window-buttons"
    "$G/term/window-buttons                     .config/gtk-4.0/window-buttons"
    "config/libinput-gestures.conf              .config/libinput-gestures.conf"
    "config/fish/config.fish                    .config/fish/config.fish"
    "config/fish/functions/fish_greeting.fish   .config/fish/functions/fish_greeting.fish"
    "config/fonts                               .local/share/fonts/glyph"
)

say() { printf '\e[38;2;215;25;33m●\e[0m %s\n' "$*"; }

extras() { # --with or a prompt -> into EXT, installs yay (and repo packages) separately from AUR
    local w; EXT=()
    if [ -z "${WITH+x}" ]; then
        say "what else to install? space-separated, Enter -- nothing"
        for w in "${!EXTRA[@]}"; do printf '  %-9s %s\n' "$w" "${EXTRA[$w]}"; done
        read -rp "  > " WITH || true
    fi
    for w in ${WITH//,/ }; do
        [ -n "${EXTRA[$w]-}" ] || { echo "no such option: $w (available: ${!EXTRA[*]})"; exit 1; }
        EXT+=(${EXTRA[$w]})
    done
}

packages() {
    say "pacman"
    # pulseaudio modules require pulseaudio itself -- pacman would not let us replace it with pipewire-pulse.
    # As a list, not grep '^pulseaudio-': pulseaudio-alsa and pulseaudio-qt live fine with pipewire
    local pa; pa=$(pacman -Qq pulseaudio-{bluetooth,jack,lirc,rtp,zeroconf,equalizer,equalizer-ladspa} 2>/dev/null || true)
    [ -z "$pa" ] || sudo pacman -R $pa
    pacman -Q pulseaudio &>/dev/null && say "pacman will ask \"Remove pulseaudio?\" -- answer y, pipewire-pulse replaces it"
    # no --noconfirm: on a conflict (pulseaudio -> pipewire-pulse) it would answer "no" and fail the install
    sudo pacman -Syu --needed "${PACMAN[@]}"

    if ! command -v yay >/dev/null; then
        say "yay"
        local tmp; tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi

    say "aur"
    # AUR is optional: if a package fails, we still install services and links
    yay -S --needed --noconfirm "${AUR[@]}" || say "aur: not everything installed, see above"
    # separately: if spicetify failed to build, the AUR core is unaffected
    [ ${#EXT[@]} -eq 0 ] || yay -S --needed --noconfirm "${EXT[@]}" || say "optional: not everything installed, see above"
}

plugins() { # hyprbars -- the window title bars (config/hypr/hyprland/titlebars.lua), built by hyprpm
    say "plugins (hyprpm)"
    if ! command -v hyprpm >/dev/null; then
        # hyprpm used to ship inside the hyprland package; it is a package of its own now,
        # and a system installed before the split (or without it) has no hyprpm at all
        say "hyprpm missing -- installing the hyprpm package"
        sudo pacman -S --needed hyprpm || true
    fi
    if ! command -v hyprpm >/dev/null; then
        # loud on purpose: without hyprpm there are no title bars, and a silent skip here
        # is exactly how a first login ends up with "unknown config key plugin.hyprbars.*"
        say "WARNING: hyprpm is still not available -- window title bars will NOT work"
        say "fix: sudo pacman -S hyprpm, then hyprpm add https://github.com/hyprwm/hyprland-plugins && hyprpm enable hyprbars"
        return 0
    fi
    # add errors out when the repo is already there -- that is what a re-run looks like
    hyprpm add https://github.com/hyprwm/hyprland-plugins 2>/dev/null || true
    # no session is running during install: enable only records it, execs.lua loads it at login
    if hyprpm enable hyprbars; then
        say "hyprbars enabled -- window title bars are on from the next login"
    else
        say "hyprpm: hyprbars could not be enabled -- no title bars"
    fi
    say "after every Hyprland upgrade the plugin goes stale: hyprpm update (then hyprpm reload or relog)"
}

services() {
    say "services"
    sudo systemctl enable NetworkManager bluetooth power-profiles-daemon
    systemctl is-enabled -q display-manager.service 2>/dev/null || sudo systemctl enable sddm
    systemctl --user enable pipewire-pulse.socket wireplumber ydotool
    sudo usermod -aG input,video "$USER" # ydotool (uinput), brightnessctl
    xdg-user-dirs-update
}

links() {
    say "symlinks (old -> $BACKUP)"
    local src dst
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        src="$DOTS/$src" dst="$HOME/$dst"
        [ "$(readlink "$dst")" = "$src" ] && continue
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
            mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        echo "  $dst"
    done
    # rules.json and kitty.conf are created by the shell itself; rice starts glyph and builds the folder theme
    mkdir -p "$HOME/.config/demonshot" "${XDG_STATE_HOME:-$HOME/.local/state}/rice"
    echo glyph > "${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell"
    mkdir -p "$HOME/Pictures/Wallpapers" # wallpaper picker (Super+Shift+W) looks here
    # the five starter wallpapers (assets/wallpapers, CC0 -- generated for the rice): copied, never
    # overwriting -- once they're yours they're yours (AMM021's installer does the same)
    local w
    for w in "$DOTS"/assets/wallpapers/*.jpg; do [ -e "$HOME/Pictures/Wallpapers/$(basename "$w")" ] || cp "$w" "$HOME/Pictures/Wallpapers/"; done
    fc-cache -f >/dev/null
    command -v gsettings >/dev/null || return 0 # --links on a system without GNOME schemas
    # dark mode for Zen, Electron and libadwaita (through the portal) and a dark gtk3 base for our gtk.css
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
    # window buttons for apps that read it from here (the rest read settings.ini):
    # close and maximise, on the left -- maximise works for these apps (rules.lua
    # exempts them from the maximise suppression); minimise is not rendered
    # because its click cannot work on Hyprland (see term/gtk-3.0/settings.ini)
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,maximize:appmenu'
}

browser_cleanup() { # firefox/zen: take OUT the inTitlebar user.js snippet older installs deployed.
    # Browsers are own-buttons apps now (rules.lua): they keep their built-in buttons, so the
    # pref must not be set anywhere -- a profile that kept it would draw no buttons of its own
    # AND get no hyprbar: a buttonless window. This removes exactly what the old step shipped:
    # the whole user.js where it consists of the snippet alone, and just the snippet where it
    # was appended to the user's own file (the rest stays byte-identical). Safe to re-run:
    # a profile without the snippet is left untouched.
    say "browser cleanup (firefox/zen user.js)"
    local marker='// glyph -- window buttons (see README: "Window buttons")'
    local pref='user_pref("browser.tabs.inTitlebar", 0);'
    # everywhere firefox/zen keep profiles: the native homes, and the flatpak homes --
    # a flatpak's profile store sits under ~/.var/app/<app id>/, invisible to a plain
    # ~/.mozilla glob (a flatpak firefox is the common CachyOS install). Zen's flatpak
    # id is app.zen_browser.zen (io.github.zen_browser.zen before 1.6); its tarball
    # builds profile under ~/.config/zen instead of ~/.zen.
    local bases=(
        "$HOME/.mozilla/firefox"
        "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"
        "$HOME/.zen"
        "$HOME/.config/zen"
        "$HOME/.var/app/app.zen_browser.zen/.zen"
        "$HOME/.var/app/io.github.zen_browser.zen/.zen"
    )
    # collect the profile dirs: the usual *.default* names (zen spells it *.Default*),
    # plus whatever profiles.ini registers -- a profile can live under any name there
    local dirs=() base d p
    for base in "${bases[@]}"; do
        [ -d "$base" ] || continue # layout not present on this machine -- nothing to do
        for d in "$base"/*.default*/ "$base"/*.Default*/; do
            [ -d "$d" ] && dirs+=("${d%/}")
        done
        if [ -f "$base/profiles.ini" ]; then
            while IFS= read -r p; do
                case "$p" in /*) d="$p" ;; *) d="$base/$p" ;; esac
                [ -d "$d" ] && dirs+=("$d")
            done < <(awk -F= '$1 == "Path" || $1 == "Default" { sub(/^[^=]*=/, ""); print }' "$base/profiles.ini" || true)
        fi
    done
    local uniq=() seen target cleaned=0 removed=0 clean=0 tmp
    for d in "${dirs[@]}"; do
        # the same dir can arrive via a glob and via profiles.ini -- clean it once
        seen=0
        for p in "${uniq[@]}"; do [ "$p" = "$d" ] && { seen=1; break; }; done
        [ "$seen" -eq 0 ] && uniq+=("$d")
    done
    for d in "${uniq[@]}"; do
        target="$d/user.js"
        [ -f "$target" ] || continue
        if ! grep -qF "$pref" "$target" && ! grep -qF "$marker" "$target"; then
            clean=$((clean + 1)) # nothing of ours in there -- leave the file exactly as it is
            continue
        fi
        # a copy goes to the backup before the file is touched, like every other edit here
        mkdir -p "$BACKUP/$(dirname "${target#"$HOME"/}")"
        cp "$target" "$BACKUP/${target#"$HOME"/}"
        tmp="$(mktemp)"
        # drop our block (the marker line, its comment lines, the pref line, and the blank
        # line the old step put in front of the block) plus any lone pref line; keep the rest
        awk -v marker="$marker" -v pref="$pref" '
            $0 == marker { inblock = 1; if (n > 0 && buf[n] == "") n--; next }
            inblock && $0 == pref { inblock = 0; next }
            inblock && /^\/\// { next }
            inblock { inblock = 0 }
            $0 == pref { next }
            { buf[++n] = $0 }
            END { for (i = 1; i <= n; i++) print buf[i] }
        ' "$target" >"$tmp"
        if [ -s "$tmp" ]; then
            cat "$tmp" >"$target" # in place: same file, its permissions survive
            cleaned=$((cleaned + 1))
            echo "  $target (snippet removed)"
        else
            rm "$target" # the file was the snippet alone
            removed=$((removed + 1))
            echo "  $target (was only the snippet -- deleted)"
        fi
        rm -f "$tmp"
    done
    if [ ${#uniq[@]} -eq 0 ]; then
        say "browser cleanup: no firefox/zen profiles found -- nothing to remove"
    elif [ $((cleaned + removed)) -eq 0 ]; then
        say "browser cleanup: $clean profile(s) already clean"
    else
        say "browser cleanup: $cleaned cleaned, $removed removed, $clean already clean -- restart the browser"
    fi
}

tmux_theme() { # tmux follows the palette: Theme.apps() writes ~/.config/tmux/theme.conf, but it only
    # colours anything if tmux.conf sources it -- add that line to an existing config (either home).
    # No tmux, or no config, or the line already there: nothing to do (AMM021's installer does the same)
    command -v tmux >/dev/null || return 0
    local conf
    for conf in "$HOME/.config/tmux/tmux.conf" "$HOME/.tmux.conf"; do
        [ -f "$conf" ] || continue
        grep -qs 'tmux/theme.conf' "$conf" && return 0
        echo 'source-file -q ~/.config/tmux/theme.conf # glyph: colors written by the shell' >> "$conf"
        echo "  $conf (+ theme.conf source)"
        return 0
    done
}

flatpak_gtk() { # flatpak apps are sandboxed off from ~/.config/gtk-* -- grant the installed ones read access,
    # or their headerbar buttons never see the gtk.css discs (GNOME Calculator is usually a flatpak).
    # Read-only and per-app; the button-layout the apps already show comes from gsettings, which does reach them.
    command -v flatpak >/dev/null || return 0
    say "flatpak gtk access"
    local apps=(org.gnome.Calculator org.gnome.Nautilus org.gnome.TextEditor org.gnome.Loupe org.gnome.Papers
                org.gnome.Calendar org.gnome.Clocks org.gnome.Contacts org.gnome.Weather org.gnome.Characters)
    local installed app
    installed="$(flatpak list --app --columns=application 2>/dev/null || true)"
    for app in "${apps[@]}"; do
        grep -qx "$app" <<<"$installed" || continue # not installed as a flatpak -- nothing to grant
        # already granted (by us or by hand): a re-run changes nothing
        flatpak override --user --show "$app" 2>/dev/null | grep -q 'gtk-4.0' && continue
        if flatpak override --user "$app" --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro; then
            echo "  $app"
        else
            say "flatpak: could not grant gtk config access to $app"
        fi
    done
}

greeter() { # boot login: greetd + the lock's face as the greeter (./install.sh --greeter).
    # Replaces the current display manager -- deliberately NOT part of the default run.
    # Order is the safety story: packages, files and config all land first; the DM swap is
    # the very last step, so a failure anywhere above leaves the old login untouched.
    say "greeter (greetd)"
    sudo pacman -S --needed "${GREETER_PACMAN[@]}"

    # the shell config at a system path: the greeter runs as the "greeter" user and cannot
    # read ~/.config. A copy, not a symlink -- re-run --greeter after a pull to refresh it
    if ! sudo diff -qr "$DOTS/$G" /etc/greetd/glyph >/dev/null 2>&1; then
        sudo rm -rf /etc/greetd/glyph
        sudo mkdir -p /etc/greetd
        sudo cp -r "$DOTS/$G" /etc/greetd/glyph
        echo "  /etc/greetd/glyph"
    fi
    sudo chmod -R go+rX /etc/greetd/glyph # root-owned repo files are group-only: the greeter user needs read+traverse

    # the fonts, system-wide: the greeter user cannot see ~/.local/share/fonts either --
    # without this the Doto clock falls back to a default font and the face is not the face
    if ! diff -qr "$DOTS/config/fonts" /usr/share/fonts/glyph >/dev/null 2>&1; then
        sudo mkdir -p /usr/share/fonts/glyph
        sudo cp "$DOTS/config/fonts"/*.ttf "$DOTS/config/fonts"/*.otf "$DOTS/config/fonts"/OFL.txt /usr/share/fonts/glyph/
        sudo fc-cache -f >/dev/null
        echo "  /usr/share/fonts/glyph"
    fi

    # profile photos for the greeter face: the greeter user cannot read a ~/.face inside a
    # 700 home, so each human user's face gets a world-readable copy of its own (the face
    # itself is not a secret -- AccountsService keeps the same file world-readable too).
    # No ~/.face -- nothing copied for that user, and their face falls back to dots.
    sudo mkdir -p /etc/greetd/faces
    local gu guid ghome
    while IFS=: read -r gu _ guid _ _ ghome _; do
        { [ "$guid" -ge 1000 ] && [ "$guid" -lt 60000 ] && [ -f "$ghome/.face" ]; } 2>/dev/null || continue
        sudo cp "$ghome/.face" "/etc/greetd/faces/$gu"
        sudo chmod 644 "/etc/greetd/faces/$gu"
        echo "  /etc/greetd/faces/$gu"
    done < <(getent passwd)

    # greetd's own files (config, the stripped compositor config, the launcher script):
    # a changed one that already exists goes to the backup first -- once, only on change
    local f
    for f in config.toml hyprland.lua glyph-greeter; do
        sudo cmp -s "$DOTS/config/greetd/$f" "/etc/greetd/$f" && continue
        if [ -e "/etc/greetd/$f" ]; then
            mkdir -p "$BACKUP/etc/greetd"
            sudo cp "/etc/greetd/$f" "$BACKUP/etc/greetd/$f"
            sudo chown "$USER" "$BACKUP/etc/greetd/$f"
            echo "  old /etc/greetd/$f -> $BACKUP/etc/greetd/$f"
        fi
        sudo mkdir -p /etc/greetd
        sudo cp "$DOTS/config/greetd/$f" "/etc/greetd/$f"
        echo "  /etc/greetd/$f"
    done
    sudo chmod 755 /etc/greetd/glyph-greeter

    # the swap -- only now, with greetd installed and configured. Which DM is on today:
    local old=""
    if [ -L /etc/systemd/system/display-manager.service ]; then
        old="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
    fi
    [ "$old" = greetd ] && old="" # a re-run: greetd already is the display manager
    if [ -n "$old" ]; then
        mkdir -p "$BACKUP"
        echo "$old" > "$BACKUP/previous-display-manager.txt"
        sudo systemctl disable "$old"
        echo "  disabled: $old (recorded in $BACKUP/previous-display-manager.txt)"
    fi
    if systemctl is-enabled -q greetd 2>/dev/null; then
        echo "  greetd already enabled"
    else
        sudo systemctl enable greetd
        echo "  enabled: greetd"
    fi

    say "greeter is the boot login from the next reboot"
    if [ -n "$old" ]; then
        say "rollback: sudo systemctl disable greetd && sudo systemctl enable $old"
        say "  (greetd's config backup, if any, is in $BACKUP/etc/greetd/ -- cp it back to /etc/greetd/)"
    else
        say "rollback: sudo systemctl disable greetd, then enable your old display manager"
    fi
    say "no login screen at boot? Ctrl+Alt+F3 -> log in on the text console -> run the rollback"
}


[ "$EUID" -eq 0 ] && { echo "run as your user, sudo will ask by itself"; exit 1; }

case "${1:-}" in
    --links) links; browser_cleanup; flatpak_gtk; tmux_theme ;; # on any distribution (NixOS, Fedora...): packages are up to you then, list in README
    --greeter) command -v pacman >/dev/null || { echo "the greeter step installs greetd with pacman (Arch only)"; exit 1; }
        greeter ;;
    ""|--with) command -v pacman >/dev/null || { echo "I only install packages on Arch; on another distribution: $0 --links"; exit 1; }
        [ "${1:-}" = --with ] && WITH="${*:2}" # both comma- and space-separated
        extras; packages; plugins; services; links; browser_cleanup; flatpak_gtk; tmux_theme
        # spicetify needs Spotify already downloaded and logged in, so there is nothing to apply before the first launch
        [[ " ${WITH//,/ } " == *" spotify "* ]] && say "spotify: launch it, log in, then spicetify config custom_apps marketplace && spicetify backup apply"
        say "done. reboot and pick Hyprland in sddm" ;;
    *) echo "usage: $0 [--with telegram,spotify,clash | --links | --greeter]"; exit 1 ;;
esac
