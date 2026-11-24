#!/bin/sh
# Lays out the apt and yum repositories the GitHub Pages site serves:
#
#   deb/pool/<suite>/*.deb, deb/dists/<suite>/main/binary-<arch>/Packages, deb/dists/<suite>/Release
#   rpm/<suite>/*.rpm and its repodata/
#
# The suites are snapshot (builds of a branch) and stable (builds of release
# tags), told apart by the version. With GPG_PRIVATE_KEY in the environment
# (an ASCII-armoured key without a passphrase) the Release files and the
# RPMs are signed and the public key is published as KEY.gpg and KEY.asc.
#
# The site's own address and the repository it is built from are taken
# from SITE_URL and REPO_URL (the workflow sets them from the repository
# it runs in, so a fork serves itself); ORIGIN names the apt Origin.
#
# Usage: repo-build.sh SITE_DIR PACKAGES_DIR...
# Needs dpkg-dev, apt-utils, rpm and createrepo-c; gnupg to sign.
set -eu
site=$1
shift
site_url=${SITE_URL:-https://sol1.github.io/ascender-packaging}
repo_url=${REPO_URL:-https://github.com/sol1/ascender-packaging}
origin=${ORIGIN:-sol1}
repo_name=${repo_url#https://github.com/}

rm -rf "$site"
mkdir -p "$site/deb/pool/snapshot" "$site/deb/pool/stable" "$site/rpm/snapshot" "$site/rpm/stable"
for dir in "$@"; do
	find "$dir" -type f \( -name '*.deb' -o -name '*.rpm' \) | while read -r f; do
		# The suite comes from the version inside the package: a release
		# asset's name cannot hold the ~ of a snapshot version.
		case $f in
		*.deb) version=$(dpkg-deb -f "$f" Version) ;;
		*.rpm) version=$(rpm -qp --qf '%{VERSION}' "$f" 2>/dev/null) ;;
		esac
		case $version in
		0~git*) suite=snapshot ;;
		*) suite=stable ;;
		esac
		case $f in
		*.deb) cp "$f" "$site/deb/pool/$suite/" ;;
		*.rpm) cp "$f" "$site/rpm/$suite/" ;;
		esac
	done
done

keyid=""
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
	export GNUPGHOME
	GNUPGHOME=$(mktemp -d)
	printf '%s' "$GPG_PRIVATE_KEY" | gpg --batch --import
	keyid=$(gpg --batch --list-secret-keys --with-colons | awk -F: '$1 == "sec" { print $5; exit }')
	gpg --batch --export "$keyid" >"$site/KEY.gpg"
	gpg --batch --armor --export "$keyid" >"$site/KEY.asc"
fi

for suite in snapshot stable; do
	(
		cd "$site/deb"
		for arch in amd64 arm64; do
			mkdir -p "dists/$suite/main/binary-$arch"
			dpkg-scanpackages --multiversion --arch "$arch" "pool/$suite" >"dists/$suite/main/binary-$arch/Packages" 2>/dev/null
			gzip -9 -k -f "dists/$suite/main/binary-$arch/Packages"
		done
		apt-ftparchive \
			-o APT::FTPArchive::Release::Origin="$origin" \
			-o APT::FTPArchive::Release::Label="Ascender packages" \
			-o APT::FTPArchive::Release::Suite="$suite" \
			-o APT::FTPArchive::Release::Codename="$suite" \
			-o APT::FTPArchive::Release::Architectures="amd64 arm64" \
			-o APT::FTPArchive::Release::Components=main \
			release "dists/$suite" >"dists/$suite/Release"
		if [ -n "$keyid" ]; then
			gpg --batch --yes --local-user "$keyid" --detach-sign --armor -o "dists/$suite/Release.gpg" "dists/$suite/Release"
			gpg --batch --yes --local-user "$keyid" --clearsign -o "dists/$suite/InRelease" "dists/$suite/Release"
		fi
	)
	if [ -n "$keyid" ] && ls "$site/rpm/$suite"/*.rpm >/dev/null 2>&1; then
		rpm --define "_gpg_name $keyid" --define "_gpg_path $GNUPGHOME" --addsign "$site/rpm/$suite"/*.rpm
	fi
	createrepo_c --quiet "$site/rpm/$suite"
done

if [ -n "$keyid" ]; then
	signed="signed with the key at <a href=\"KEY.gpg\">KEY.gpg</a>"
	apt_source="sudo curl -fsSL -o /etc/apt/keyrings/ascender.gpg $site_url/KEY.gpg
echo \"deb [signed-by=/etc/apt/keyrings/ascender.gpg] $site_url/deb snapshot main\" | sudo tee /etc/apt/sources.list.d/ascender.list"
	yum_check="gpgcheck=1
gpgkey=$site_url/KEY.asc"
else
	signed="not signed yet"
	apt_source="echo \"deb [trusted=yes] $site_url/deb snapshot main\" | sudo tee /etc/apt/sources.list.d/ascender.list"
	yum_check="gpgcheck=0"
fi
cat >"$site/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>Ascender packages</title>
<style>body{font:15px/1.5 system-ui,sans-serif;max-width:48rem;margin:3rem auto;padding:0 1rem}pre{background:#f4f4f4;padding:.75rem;overflow-x:auto}</style>
<h1>Ascender packages</h1>
<p>Debian and RPM packages of <a href="https://github.com/ctrliq/ascender">Ascender</a> (the Go rewrite), built by
<a href="$repo_url">$repo_name</a>. The packages are $signed.
The <code>snapshot</code> suite holds builds of a branch; <code>stable</code> holds builds of release tags.</p>
<h2>Debian 13 and Ubuntu</h2>
<pre>sudo apt-get install -y ca-certificates curl
$apt_source
sudo apt-get update
sudo apt-get install ascender        # a complete single node, or ascender-web, ascender-task, ascender-node</pre>
<h2>Rocky Linux 9 and other EL9</h2>
<pre>sudo dnf install -y epel-release     # receptor, for execution nodes
sudo tee /etc/yum.repos.d/ascender.repo &lt;&lt;'EOF'
[ascender]
name=Ascender packages
baseurl=$site_url/rpm/snapshot
enabled=1
$yum_check
EOF
sudo dnf install ascender</pre>
<p><a href="deb/">deb/</a> · <a href="rpm/">rpm/</a> · <a href="$repo_url/releases">every build</a></p>
HTML
du -sh "$site"
