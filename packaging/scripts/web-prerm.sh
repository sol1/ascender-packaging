#!/bin/sh
# ascender-web: stop and disable the service when the package is removed (not on upgrade).
set -e
[ -d /run/systemd/system ] || exit 0
case "$1" in
remove | 0)
	systemctl disable --now --quiet ascender-web || true
	;;
esac
