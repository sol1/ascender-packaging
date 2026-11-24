#!/bin/sh
# Builds the two Ascender binaries for one architecture, as the upstream
# images do (static, trimmed, stripped), and collects what the packages
# ship beside them: the documentation site the web server renders, the
# licence files.
#
# Usage: build-binaries.sh SOURCE_DIR ARCH BUILD_DIR
set -eu
src=$1
arch=$2
build=$3
bin="$build/bin/$arch"
share="$build/share"

mkdir -p "$bin" "$share"
bin=$(cd "$bin" && pwd)
for cmd in ascender-web ascender-task; do
	echo "building $cmd for linux/$arch"
	(cd "$src/src" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -trimpath -ldflags='-s -w' -o "$bin/$cmd" "./cmd/$cmd")
done

rm -rf "$share/docs" "$share/licenses"
cp -r "$src/docs/docsite" "$share/docs"
cp -r "$src/licenses" "$share/licenses"
cp "$src/LICENSE" "$src/NOTICE.txt" "$share/"
# nfpm takes a tree's modes from the files: plain files 0644, directories 0755.
find "$share" -type d -exec chmod 0755 {} + 
find "$share" -type f -exec chmod 0644 {} +
