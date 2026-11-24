#!/bin/sh
# Runs tests/smoke.sh in a Debian 13 and a Rocky Linux 9 container with
# docker (or podman: RUNTIME=podman), each with a PostgreSQL container
# beside it, against the packages in build/packages.
#
#   VERSION=$(scripts/version.sh ../ascender-go) tests/run-local.sh [debian|rocky]
set -eu
: "${VERSION:?set VERSION to the packages' version}"
rt=${RUNTIME:-docker}
here=$(cd "$(dirname "$0")/.." && pwd)
which=${1:-all}
net=ascender-smoke-$$
"$rt" network create "$net" >/dev/null
cleanup() {
	"$rt" rm -f "$net-pg" >/dev/null 2>&1 || true
	"$rt" network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
"$rt" run -d --rm --name "$net-pg" --network "$net" --network-alias postgres \
	-e POSTGRES_USER=ascender -e POSTGRES_PASSWORD=ascender -e POSTGRES_DB=ascender docker.io/library/postgres:17 >/dev/null
status=0
for image in debian:13 rockylinux:9; do
	case "$which:$image" in all:* | debian:debian* | rocky:rocky*) ;; *) continue ;; esac
	echo "=== $image"
	"$rt" exec "$net-pg" sh -c 'until pg_isready -q -h 127.0.0.1; do sleep 1; done; psql -U ascender -q -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public"' >/dev/null
	"$rt" run --rm --network "$net" -e VERSION="$VERSION" -e PGHOST=postgres \
		-v "$here/build/packages:/packages:ro" -v "$here/tests/smoke.sh:/smoke.sh:ro" "docker.io/library/$image" sh /smoke.sh || status=1
done
exit $status
