#!/bin/sh
# A first installation sets the node up; an upgrade leaves it alone (the
# web and task packages restart their services).
set -e
case "$1" in
configure) [ -n "${2:-}" ] || /usr/libexec/ascender/setup-single-node ;;
1) /usr/libexec/ascender/setup-single-node ;;
esac
