#!/bin/bash
set -e

# why using mpd in sandbox?
#   because mpd in fedora pulls huge deps.
#
# pre:
#   install mpd, pipewire;
#   create dir ~/.mpd; (so it can be binded by bwrap)
# usage:
#   start with option --no-daemon;

mpd="/usr/bin/mpd"

flags=(
    # env:
    --clearenv
    # basic
    --setenv PATH /usr/bin --setenv USER "$USER" --setenv HOME ~
    # app
    --setenv XDG_RUNTIME_DIR "$XDG_RUNTIME_DIR"
    # lib and bin
    # check lib path via `file {binary}`.
    --ro-bind ~/.sandbox/alpine/usr /usr
    --ro-bind ~/.sandbox/alpine/lib /lib
    --tmpfs /tmp

    # proc, sys, dev
    --proc /proc
    --dev /dev

    # sound (pipewire)
    --ro-bind /run/user/"$UID"/pipewire-0 /run/user/"$UID"/pipewire-0
    # sound (pulseaudio); use it even if using pipewire-pulse.
    --ro-bind /run/user/"$UID"/pulse /run/user/"$UID"/pulse

    # NOTE: (security)
    # --bind a/ then --ro-bind a/b (file), a/b is ro in sandbox;
    # but if we modify a/b (change fd), then a/b will be rw!
    # so, do not use --ro-bind inside --bind.

    # app
    --bind ~/.mpd/ ~/.mpd/
    --ro-bind ~/music/ ~/music/
    --ro-bind ~/.config/mpd/ ~/.config/mpd/

    # network.
    --unshare-all #--share-net

    # security
    --die-with-parent --new-session
)

# NOTE: specify --no-daemon in mpd!
exec bwrap "${flags[@]}" -- "$mpd" "$@"
