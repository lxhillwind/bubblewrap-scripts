#!/bin/bash
set -e

qemu="/bin/qemu-system-x86_64"

spice_socket_dir=/tmp/vm_spice/
mkdir -p "$spice_socket_dir"

# bwrap (bubblewrap) is required.

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
    --setenv PATH "$HOME/bin":/usr/bin --setenv USER "$USER" --setenv HOME ~
    # app
    --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    # lib and bin
    --ro-bind /usr /usr
    --symlink /usr/lib64 /lib64
    --symlink /usr/bin /bin

    # samba. (NOTE: samba seems not work in openSUSE)
    --ro-bind /etc/passwd /etc/passwd
    # fedora. (fix some missing .so; get this by `ls -l ...`)
    --ro-bind /etc/alternatives/ /etc/alternatives/

    # proc, sys, dev
    --proc /proc
    # --ro-bind /sys /sys; see https://wiki.archlinux.org/title/Bubblewrap
    --ro-bind /sys/dev/char /sys/dev/char
    --ro-bind /sys/devices/pci0000:00 /sys/devices/pci0000:00
    --dev /dev
    --dev-bind /dev/dri /dev/dri
    # required for kvm.
    --dev-bind /dev/kvm /dev/kvm

    # timezone.
    --ro-bind /etc/localtime /etc/localtime
    # font and network (also --share-net)
    --ro-bind /etc/fonts/ /etc/fonts/ --ro-bind /etc/resolv.conf /etc/resolv.conf

    # set ~ before gui (xauthority)
    --tmpfs ~
    "${flags_gui[@]}"

    # sound (pipewire)
    --ro-bind /run/user/"$UID"/pipewire-0 /run/user/"$UID"/pipewire-0
    # sound (pulseaudio); use it even if using pipewire-pulse.
    --ro-bind /run/user/"$UID"/pulse /run/user/"$UID"/pulse

    # NOTE: (security)
    # --bind a/ then --ro-bind a/b (file), a/b is ro in sandbox;
    # but if we modify a/b (change fd), then a/b will be rw!
    # so, do not use --ro-bind inside --bind.

    # app

    --tmpfs /tmp
    --bind "$spice_socket_dir" "$spice_socket_dir"
    --setenv TMPDIR "$spice_socket_dir"

    --bind ~/qemu/ ~/qemu/
    --ro-bind ~/iso/ ~/iso/
    --chdir ~/qemu/

    # this is to make xdg-open work (optional?)
    --setenv XDG_CURRENT_DESKTOP X-GENERIC

    # network.
    --unshare-all --share-net

    # security
    --die-with-parent --new-session
)

# -L option is workaround for `qemu: could not load PC BIOS 'bios-256k.bin'`.
# (in sandbox)
# see https://unix.stackexchange.com/questions/134893/cannot-start-kvm-vm-because-missing-bios

# opensuse
#exec bwrap "${flags[@]}" -- "$qemu" -L /usr/share/qemu/ "$@"
# fedora
exec bwrap "${flags[@]}" -- "$qemu" -L /usr/share/seabios/ -L /usr/share/qemu/ -L /usr/share/ipxe/qemu/ -L /usr/share/seavgabios/ "$@"
