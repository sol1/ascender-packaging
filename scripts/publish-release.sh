#!/bin/sh
# Publishes the packages in a directory as a GitHub release of this
# repository (scripts/release-tag.sh names it: a prerelease for a snapshot). Then removes snapshot releases
# older than the KEEP_SNAPSHOTS newest (default 5); releases of tags stay.
#
# Usage: publish-release.sh VERSION PACKAGES_DIR SOURCE_REPO SOURCE_SHA
set -eu
version=$1
dir=$2
source_repo=$3
source_sha=$4
keep=${KEEP_SNAPSHOTS:-5}

tag=$("$(dirname "$0")/release-tag.sh" "$version")
case $version in
0~git*)
	flags="--prerelease"
	title="Snapshot $version"
	;;
*)
	flags=""
	title="Ascender $version"
	;;
esac
notes="Built from https://github.com/$source_repo/commit/$source_sha by the packages workflow."

if ! gh release view "$tag" >/dev/null 2>&1; then
	# shellcheck disable=SC2086
	gh release create "$tag" $flags --title "$title" --notes "$notes"
fi
find "$dir" -type f \( -name '*.deb' -o -name '*.rpm' \) -print0 | xargs -0 gh release upload "$tag" --clobber

gh release list --limit 200 --json tagName,createdAt --jq '[.[] | select(.tagName | startswith("snapshot-"))] | sort_by(.createdAt) | reverse | .['"$keep"':] | .[].tagName' |
	while read -r old; do
		echo "removing old snapshot release $old"
		gh release delete "$old" --yes --cleanup-tag
	done
