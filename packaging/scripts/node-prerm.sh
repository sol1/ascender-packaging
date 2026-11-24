#!/bin/sh
set -e
[ -d /run/systemd/system ] || exit 0
case "$1" in
remove | 0)
	systemctl disable --now --quiet ascender-node || true
	;;
esac
