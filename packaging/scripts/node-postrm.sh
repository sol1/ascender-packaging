#!/bin/sh
# Give the distribution's receptor.service back when the package goes.
set -e
[ -d /run/systemd/system ] || exit 0
case "$1" in
remove | purge | 0)
	systemctl unmask --quiet receptor.service 2>/dev/null || true
	systemctl daemon-reload || true
	;;
esac
