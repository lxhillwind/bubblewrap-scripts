#!/bin/bash
set -e

remote_viewer="/usr/bin/remote-viewer"

mkdir -p /tmp/vm_spice/

flags_alpine=(
    --ro-bind ~/.sandbox/alpine/usr /usr
    --ro-bind ~/.sandbox/alpine/bin /bin
    --ro-bind ~/.sandbox/alpine/lib /lib
    # /usr/share/fonts dir may not exist yet:
    #   bwrap: Can't mkdir XXX: Read-only file system
    # create <path-to-sandbox>/usr/share/fonts manually if necessary.
    --ro-bind /usr/share/fonts /usr/share/fonts
    --ro-bind /etc/fonts /etc/fonts
)
flags_fedora=(
    --ro-bind /usr /usr
    --ro-bind /bin /bin
    --ro-bind /lib64 /lib64
    --ro-bind /etc/fonts /etc/fonts

    # fix missing lib
    --ro-bind /etc/ld.so.conf /etc/ld.so.conf
    --ro-bind /etc/ld.so.conf.d /etc/ld.so.conf.d
    --ro-bind /etc/ld.so.cache /etc/ld.so.cache
    --ro-bind /etc/alternatives /etc/alternatives
)

if [ -n "$WAYLAND_DISPLAY" ]; then
    # wayland
    flags_gui=(
        --setenv WAYLAND_DISPLAY "$WAYLAND_DISPLAY"
        --ro-bind /run/user/"$UID"/"$WAYLAND_DISPLAY" /run/user/"$UID"/"$WAYLAND_DISPLAY"
    )
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
    --setenv PATH /usr/bin --setenv USER "$USER" --setenv HOME ~
    # app
    --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"

    # lib and bin
    #"${flags_alpine[@]}"
    "${flags_fedora[@]}"

    --tmpfs /tmp

    # proc, sys, dev
    --proc /proc
    # --ro-bind /sys /sys; see https://wiki.archlinux.org/title/Bubblewrap
    --ro-bind /sys/dev/char /sys/dev/char
    --ro-bind /sys/devices/pci0000:00 /sys/devices/pci0000:00
    --dev /dev
    # for gl?
    --dev-bind /dev/dri/ /dev/dri/

    # network (also --share-net)
    --ro-bind /etc/resolv.conf /etc/resolv.conf
    # ssl
    --ro-bind /etc/pki/tls/cert.pem /etc/pki/tls/cert.pem

    # icon
    --setenv XCURSOR_SIZE "$XCURSOR_SIZE"
    --setenv XCURSOR_THEME "$XCURSOR_THEME"

    "${flags_gui[@]}"

    # app specific
    --bind /tmp/vm_spice/ /tmp/vm_spice/

    # network.
    --unshare-all --share-net

    # security
    --new-session
    --die-with-parent
)

exec bwrap "${flags[@]}" -- "$remote_viewer" "$@"
