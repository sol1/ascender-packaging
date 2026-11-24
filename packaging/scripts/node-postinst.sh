#!/bin/sh
# The distribution's receptor.service runs receptor as root from
# /etc/receptor/receptor.conf, which listens on 7323 without TLS and accepts
# work: masked, so only the ascender-node service runs receptor on this
# host. ascender-node is enabled; it starts once receptor.conf is written.
set -e
[ -d /run/systemd/system ] || exit 0
systemctl daemon-reload || true
if [ -f /usr/lib/systemd/system/receptor.service ] || [ -f /lib/systemd/system/receptor.service ]; then
	systemctl disable --now --quiet receptor.service 2>/dev/null || true
	systemctl mask --quiet receptor.service || true
fi
systemctl enable --quiet ascender-node || true
if [ -f /etc/ascender/receptor/receptor.conf ] && systemctl is-active --quiet ascender-node; then
	systemctl restart ascender-node || true
fi
