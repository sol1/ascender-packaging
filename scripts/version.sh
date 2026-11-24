#!/bin/sh
# Prints the package version of the Ascender checkout given: the tag when
# the commit is tagged v<version>, otherwise a snapshot version made of the
# commit's date and time (UTC) and its abbreviated hash. A snapshot version
# starts with 0~ so that every release sorts above it, in apt and in dnf,
# and a newer commit of one branch sorts above an older one.
set -eu
src=$1
tag=$(git -C "$src" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)
if [ -n "$tag" ]; then
	echo "${tag#v}"
	exit 0
fi
sha=$(git -C "$src" rev-parse --short=7 HEAD)
stamp=$(TZ=UTC git -C "$src" log -1 --format=%cd --date=format-local:%Y%m%d.%H%M)
echo "0~git$stamp.$sha"
