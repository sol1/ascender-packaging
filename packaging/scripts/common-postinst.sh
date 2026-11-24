#!/bin/sh
set -e
if command -v systemd-sysusers >/dev/null 2>&1; then
	systemd-sysusers /usr/lib/sysusers.d/ascender.conf
else
	getent group ascender >/dev/null || groupadd --system ascender
	getent passwd ascender >/dev/null || useradd --system --gid ascender --home-dir /var/lib/ascender --no-create-home --shell /usr/sbin/nologin --comment Ascender ascender
fi
/usr/libexec/ascender/subids
chown ascender:ascender /var/lib/ascender /var/log/ascender
chown root:ascender /etc/ascender /etc/ascender/ascender.env /etc/ascender/receptor /etc/ascender/receptor/tls /etc/ascender/receptor/tls/ca
chmod 0750 /etc/ascender /etc/ascender/receptor /etc/ascender/receptor/tls /etc/ascender/receptor/tls/ca
