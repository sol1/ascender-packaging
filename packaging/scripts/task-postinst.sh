#!/bin/sh
# ascender-task: reload systemd; restart a running service on upgrade. Not enabled
# here: the service needs its configuration first (the ascender package, or
# the installer, enables it).
set -e
[ -d /run/systemd/system ] || exit 0
systemctl daemon-reload || true
upgrade=
case "$1" in
configure) [ -z "${2:-}" ] || upgrade=1 ;;
[2-9]*) upgrade=1 ;;
esac
if [ -n "$upgrade" ] && systemctl is-active --quiet ascender-task; then
	systemctl restart ascender-task || true
fi
