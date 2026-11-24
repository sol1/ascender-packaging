#!/bin/sh
# Prints the tag of the release that holds the packages of a version:
# v<version> for a release, snapshot-<version> for a snapshot, with the ~
# of a snapshot version written as . (a git tag cannot hold ~).
set -eu
case $1 in
0~git*) echo "snapshot-$(echo "$1" | tr '~' '.')" ;;
*) echo "v$1" ;;
esac
