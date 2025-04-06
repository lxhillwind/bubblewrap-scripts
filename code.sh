#!/bin/bash
set -e

# setup:
# download vscode tar, extract to ~/.sandbox/vscode/
#
# (optional) code.desktop file: get one from <https://gist.github.com/infosec-intern/542d39e16f46ff472803a42bc50f3b4f>

# seems that we cannot open url inside vscode because of url handler missing.
#
# possible workaround:
# click url in code -> call some program in sandbox -> some program in host get notified by socket
# -> open url in host.

# dbus proxy {{{1
dbus_file=$(printf %s "$DBUS_SESSION_BUS_ADDRESS" | sed 's/unix:path=//; s/,.*//')
mkdir -p /tmp/dbus-proxy
if [ -n "$WAYLAND_DISPLAY" ]; then
    is_wayland=.wayland
else
    is_wayland=
fi
# sway does not kill flock automatically after quiting (unlike x11), so we should use different set.
dbus_file_new=/tmp/dbus-proxy/"${0##*/}$is_wayland"
touch "$dbus_file_new"
dbus_rules=(
    --talk='org.fcitx.Fcitx5'  # fcitx5
    )
# run flock to avoid duplicating xdg-dbus-proxy process;
# run in background, so error check is not required;
flock -xn "$dbus_file_new.flock" \
    xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$dbus_file_new" --filter --log \
    "${dbus_rules[@]}" &
DBUS_SESSION_BUS_ADDRESS="unix:path=$dbus_file_new"

# main {{{1
code="/opt/vscode/code"
mkdir -p ~/.code-box/home
mkdir -p ~/.code-box/vscode
mkdir -p ~/.code-box/config
mkdir -p ~/.code-box/cache-fontconfig
mkdir -p ~/.code-box/pki
mkdir -p ~/repos/UNTRUSTED
[ -e ~/.code-box/zshrc ] || printf 'source ~/.config/zshrc\n' >> ~/.code-box/zshrc
code_flags=()

flags_system=(
    # vscode lib dep
    --ro-bind /lib64/ /lib64/
    --ro-bind /etc/alternatives/ /etc/alternatives/
    --ro-bind /usr/ /usr/
    # shell, tool, etc.
    --setenv SHELL /bin/zsh
    --ro-bind /bin/ /bin/
    --tmpfs /usr/sbin/
    # --bind here to make it upgrade.
    --bind ~/.sandbox/vscode/VSCode-linux-x64 /opt/vscode
    # ssh
    --ro-bind /etc/passwd /etc/passwd
    # font
    --ro-bind /etc/fonts /etc/fonts
    # ssl
    --ro-bind /etc/pki/tls/cert.pem /etc/pki/tls/cert.pem
    # curl depends on this.
    --ro-bind /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt
    # timezone
    --ro-bind /etc/localtime /etc/localtime
    # network (also --share-net)
    --ro-bind /etc/resolv.conf /etc/resolv.conf
    # icon
    --setenv XCURSOR_SIZE "$XCURSOR_SIZE"
    --setenv XCURSOR_THEME "$XCURSOR_THEME"
    --ro-bind /usr/share/icons/ /usr/share/icons/
    )

if [ -n "$WAYLAND_DISPLAY" ]; then
    # wayland
    flags_gui=(
        --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
        --ro-bind /run/user/"$UID"/"$WAYLAND_DISPLAY" /run/user/"$UID"/"$WAYLAND_DISPLAY"
    )
    code_flags=('--enable-features=UseOzonePlatform' '--ozone-platform=wayland')
else
    # x11
    flags_gui=(
        --setenv DISPLAY "$DISPLAY"
        --ro-bind ~/.Xauthority ~/.Xauthority
    )
fi

flags=(
    # env:
    --clearenv
    # basic
    --setenv PATH /bin:/usr/bin --setenv USER "$USER" --setenv HOME ~
    # fcitx
    --setenv DBUS_SESSION_BUS_ADDRESS "$DBUS_SESSION_BUS_ADDRESS"
    --setenv QT_IM_MODULE "$QT_IM_MODULE" --setenv GTK_IM_MODULE "$GTK_IM_MODULE" --setenv XMODIFIERS "$XMODIFIERS"
    # app
    --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    --setenv LANG zh_CN.utf8
    --setenv LC_ALL zh_CN.utf8
    --setenv LC_CTYPE zh_CN.utf8

    "${flags_system[@]}"

    --tmpfs /tmp
    --ro-bind "$dbus_file_new" "$dbus_file_new"

    # proc, sys, dev
    --proc /proc
    # --ro-bind /sys /sys; see https://wiki.archlinux.org/title/Bubblewrap
    --ro-bind /sys/dev/char /sys/dev/char
    --ro-bind /sys/devices/pci0000:00 /sys/devices/pci0000:00
    --ro-bind /sys/bus/pci /sys/bus/pci
    --dev /dev
    # for webgl
    --dev-bind /dev/dri/ /dev/dri/

    --dir /run/user/"$UID"/

    # NOTE: (security)
    # --bind a/ then --ro-bind a/b (file), a/b is ro in sandbox;
    # but if we modify a/b (change fd), then a/b will be rw!
    # so, do not use --ro-bind inside --bind.

    --bind ~/.code-box/home ~
    "${flags_gui[@]}"

    # app
    --bind ~/.code-box/vscode ~/.vscode
    --bind ~/.code-box/config ~/.config/Code
    --ro-bind ~/.config/nvim ~/.config/nvim
    --ro-bind ~/vimfiles ~/vimfiles
    --ro-bind ~/.vimrc ~/.vimrc
    --bind ~/.code-box/cache-fontconfig ~/.cache/fontconfig
    --bind ~/.code-box/pki ~/.pki
    --bind ~/repos/UNTRUSTED ~/repos/UNTRUSTED

    # network.
    --unshare-all --share-net

    # security
    --new-session
    # code is run like daemon mode.
    #--die-with-parent
)

bind_option=

for i in "$@"; do
    if [ -d "$i" ]; then
        if [ -t 0 ] && [ -z "$bind_option" ]; then
            printf 'bind directory read-write? (default is read-only)\n[y/N] ' >&2
            case "$(read -s -n 1 x; printf %s "$x")" in
                y|Y)
                    bind_option=--bind
                    ;;
            esac
            echo
        fi
        if [ -z "$bind_option" ]; then
            bind_option=--ro-bind
        fi

        real_path="$(realpath "$i")"
        flags=("${flags[@]}" "$bind_option" "$real_path"  "$real_path")
    fi
done

exec bwrap "${flags[@]}" -- "$code" "${code_flags[@]}" "$@"
