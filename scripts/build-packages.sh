#!/bin/sh
# Builds the packages with nfpm from build/bin/ARCH and build/share, for the
# formats given (deb, rpm). The units are rendered first with the version
# baked in, which the server reports as its own.
#
# MAINTAINER, VENDOR and HOMEPAGE name who built the packages (the workflow
# takes them from the repository it runs in and its variables).
#
# Usage: VERSION=... ARCH=... build-packages.sh deb rpm
set -eu
: "${VERSION:?set VERSION (scripts/version.sh)}"
: "${ARCH:?set ARCH (amd64 or arm64)}"
build=${BUILD:-build}
nfpm=${NFPM:-nfpm}
MAINTAINER=${MAINTAINER:-Dave Kempe <davekempe@users.noreply.github.com>}
VENDOR=${VENDOR:-sol1}
HOMEPAGE=${HOMEPAGE:-https://github.com/sol1/ascender-packaging}

units="$build/units"
mkdir -p "$units"
for in in packaging/systemd/*.service.in; do
	sed "s|@VERSION@|$VERSION|g" "$in" >"$units/$(basename "${in%.in}")"
done

# nfpm expands environment variables in some fields only, so the
# definitions are rendered first, with every value literal.
rendered="$build/nfpm"
mkdir -p "$rendered"
for cfg in nfpm/*.yaml; do
	sed -e "s|\${VERSION}|$VERSION|g" -e "s|\${ARCH}|$ARCH|g" -e "s|\${BIN}|$build/bin/$ARCH|g" \
		-e "s|\${SHARE}|$build/share|g" -e "s|\${UNITS}|$units|g" \
		-e "s|\${MAINTAINER}|$MAINTAINER|g" -e "s|\${VENDOR}|$VENDOR|g" -e "s|\${HOMEPAGE}|$HOMEPAGE|g" "$cfg" >"$rendered/$(basename "$cfg")"
done

for fmt in "$@"; do
	out="$build/packages/$fmt"
	mkdir -p "$out"
	for cfg in "$rendered"/*.yaml; do
		name=$(basename "$cfg" .yaml)
		# Packages with no architecture-specific content are built once.
		case $name in
		ascender-common | ascender-node | ascender)
			[ "$ARCH" = amd64 ] || continue
			;;
		esac
		"$nfpm" package -f "$cfg" -p "$fmt" -t "$out/"
	done
done
ls -l "$build/packages"/*
