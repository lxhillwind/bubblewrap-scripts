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
code_flags=()

flags_system=(
    --symlink usr/lib64 /lib64
    --symlink usr/lib /lib
    --symlink usr/bin /bin
    --symlink usr/sbin /sbin

    # vscode lib dep
    --ro-bind /etc/alternatives/ /etc/alternatives/
    --ro-bind /usr/ /usr/
    # shell, tool, etc.
    --setenv SHELL /bin/zsh
    # --bind here to make it upgrade.
    --bind ~/.sandbox/vscode/VSCode-linux-x64 /opt/vscode
    # ssh
    --ro-bind /etc/passwd /etc/passwd
    # font
    --ro-bind /etc/fonts /etc/fonts
    # ssl
    --ro-bind /etc/pki/ /etc/pki/
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

    # this should be put before flags_gui.
    --bind ~/.sandbox/code-home ~

    "${flags_gui[@]}"

    # app
    --ro-bind ~/vimfiles ~/vimfiles
    --ro-bind ~/.vimrc ~/.vimrc
    --ro-bind ~/.config/zshrc ~/.config/zshrc

    # network.
    --unshare-all --share-net

    # security
    --new-session
    --die-with-parent
)

double_dash=
flags_app=()
for i in "$@"; do
    if [ -z "$double_dash" ] && [ "$i" = -- ]; then
        double_dash=1
    else
        if [ -z "$double_dash" ]; then
            flags=("${flags[@]}" "$i")
        else
            flags_app=("${flags_app[@]}" "$i")
        fi
    fi
done

exec bwrap "${flags[@]}" -- "$code" "${code_flags[@]}" -n "${flags_app[@]}"
