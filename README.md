# Ascender packaging

Debian and RPM packages of [Ascender](https://github.com/ctrliq/ascender)
(the Go rewrite), built from upstream by GitHub Actions and served from an
apt and a yum repository on GitHub Pages:

    https://sol1.github.io/ascender-packaging/

The page there has the two lines that add the repository. Every build is
also a [release](https://github.com/sol1/ascender-packaging/releases) of
this repository with the packages attached (`snapshot-0.git...`, a
prerelease, or `v<version>`).

Ascender's own deployment story is container images and the Kubernetes
operator. This repository is the other one: plain hosts, a package manager,
systemd. It is a proving ground; what works here is meant to go upstream.

## What is built

The two Ascender binaries are static (`CGO_ENABLED=0`, trimmed, stripped),
so a package is the binary, a unit, and the files around it.

| Package | Holds | Depends on |
| --- | --- | --- |
| `ascender-common` | The `ascender` user, `/etc/ascender/ascender.env`, the state directories, the licences | systemd |
| `ascender-web` | `/usr/bin/ascender-web`, `ascender-web.service` on port 8070, the documentation site it serves under `/docs/` | ascender-common |
| `ascender-task` | `/usr/bin/ascender-task`, `ascender-task.service`: the dispatcher, registering this host as a hybrid node (jobs run here through rootless podman) or a control node | ascender-common, podman and its rootless pieces |
| `ascender-node` | `ascender-node.service` running receptor as the `ascender` user, and `ascender-node-apply-bundle` | ascender-common, receptor, podman; on Debian also python3-ansible-runner |
| `ascender` | A complete single node: web, task, PostgreSQL on this host, set up and started at installation | ascender-web, ascender-task, postgresql, openssl |

Architectures: amd64 and arm64 (the Go cross-compile; the dependencies come
from the distribution). Distributions: Debian 13 and Rocky Linux 9 are what
the smoke test installs on; Ubuntu and the other EL9 rebuilds should work
the same and are not tested yet.

### Versions

A build of a branch gets a snapshot version from the commit's date, time
(UTC) and hash, `0~git20261124.1058.7bfb959`, which sorts below any release
in both apt and dnf, and later commits of a branch above earlier ones. A
build of a tag `v26.1.0` is version `26.1.0`. The server reports the
version at `/api/v2/ping/`; the units set `ASCENDER_VERSION` to it.

Snapshots go in the `snapshot` apt suite and `rpm/snapshot`; releases in
`stable`. The site serves the newest snapshot and every release, since a
Pages site is kept under a gigabyte; older snapshots stay on the releases
page, the newest five.

## Installing

### A complete single node

    apt-get install ascender          # Debian
    dnf install ascender              # Rocky Linux, after dnf install epel-release

The `ascender` package's post-install script, `/usr/libexec/ascender/setup-single-node`:

- creates the database `ascender` owned by the role `ascender` in the
  local PostgreSQL, reached over its socket as the `ascender` user with no
  password (`ASCENDER_DATABASE_URL` in `/etc/ascender/ascender.env`);
- generates `/etc/ascender/SECRET_KEY`, which encrypts credentials in the
  database (back it up with the database), and
  `/etc/ascender/ADMIN_PASSWORD`, the `admin` account's password, set at
  every start;
- makes a self-signed certificate in `/etc/ascender/tls/` so the server
  speaks HTTPS on 8070 from the start (Ascender's cookies are marked Secure
  in production mode, so plain HTTP only works through a TLS proxy or in
  development mode);
- enables and starts `ascender-web` and `ascender-task`.

Then https://host:8070/ with `admin` and the password in
`/etc/ascender/ADMIN_PASSWORD`. The first job pulls the execution
environment image into the `ascender` user's podman, so it waits a while.
Running it again fills in only what is missing.

### Web and task on separate hosts

Install `ascender-web` or `ascender-task` on each, set the same database and
copy the same `/etc/ascender/SECRET_KEY` to every host, then
`systemctl enable --now` the service. `ascender.env` lists the variables; the
units are not enabled by the packages, since they cannot start without a
database. The first process to see an empty database gives it the schema
and creates `admin`.

Every `ascender-task` host is a control plane node, named by
`ASCENDER_CLUSTER_HOST_ID` (the host name when unset). A hybrid node (the
default) also runs jobs; `ASCENDER_NODE_TYPE=control` makes one that only
controls them, for a cluster with execution nodes.

### Execution and hop nodes

On the node, install `ascender-node`. It masks the distribution's
`receptor.service` (whose default configuration listens on 7323 without
TLS and accepts work) and ships `ascender-node.service`, which runs
receptor as the `ascender` user from `/etc/ascender/receptor/receptor.conf`
once that file exists.

In Ascender, register the node and give it an address (the API's `POST
/api/v2/instances/` only works on Kubernetes):

    ascender-web provision_instance --hostname exec1.example.com --node_type execution
    ascender-web add_receptor_address --instance exec1.example.com --address exec1.example.com --port 27199 --canonical --peers_from_control_nodes

Download its install bundle (the instance's page, or `GET
/api/v2/instances/N/install_bundle/`) and apply it on the node:

    ascender-node-apply-bundle exec1.example.com_install_bundle.tar.gz

The script lays the certificates out under `/etc/ascender/receptor/`,
writes `receptor.conf` from the bundle's variables (listener, peers, the
`ansible-runner` work command with signature verification for an execution
node) and starts the service. `receptorctl --socket /run/receptor/receptor.sock status`
shows the mesh.

The control node's side is not packaged yet: the mesh CA and the work
signing key the bundle is made from (`/etc/ascender/receptor/tls/ca/mesh-CA.crt`
and `.key`, `work_private_key.pem` and `work_public_key.pem`) and the
control node's own `receptor.conf` (a `tcp-listener` the nodes dial, the
`local` work command, `work-signing`, a `tls-client` named `tlsclient`) are
the installer's job; see "Next" below. On EL, `ansible-runner` is not in
EPEL: execution nodes need `pip install ansible-runner` (hop nodes do not).

### Where things are

| Path | What |
| --- | --- |
| `/etc/ascender/ascender.env` | Environment of both services; a value here overrides the unit's |
| `/etc/ascender/SECRET_KEY`, `ADMIN_PASSWORD` | Secrets, `root:ascender` 0640 |
| `/etc/ascender/tls/` | The web server's certificate (single-node setup) |
| `/etc/ascender/receptor/` | `receptor.conf`, the mesh certificates and keys |
| `/etc/ascender/containers.conf` | Podman settings for the `ascender` user under systemd |
| `/var/lib/ascender/` | Projects, job output, the user's podman storage (execution environment images) |
| `/var/log/ascender/` | The external log queue's spool |
| `/usr/share/ascender/docs/` | The documentation site, served under `/docs/` |

Logs go to the journal: `journalctl -u ascender-web -u ascender-task`.

## Building

The source is cloned from the repository and ref in `source.env`
(`ctrliq/ascender` at `golang`). Go and [nfpm](https://nfpm.goreleaser.com)
are needed; the Go release that builds the binaries is `GOTOOLCHAIN` in the
`Makefile`, downloaded by the go command, and is bumped when a patch release
fixes something in the standard library before the source's `go.mod` moves.

    make packages                          # clone, build amd64, deb and rpm into build/packages
    make packages SOURCE_DIR=../ascender ARCH=arm64 FORMATS=deb
    make test                              # install and smoke test in Debian 13 and Rocky 9 containers (docker)
    make repo                              # the apt and yum layout in site/

`scripts/version.sh` gives the version of a checkout. `make packages
VERSION=...` overrides it.

### The workflow

`.github/workflows/build.yml` runs on push, on pull requests, nightly, and
by hand (with a repository and ref of its own, and whether to publish). It
builds both architectures, runs `tests/smoke.sh` in a Debian 13 and a Rocky
Linux 9 container against a PostgreSQL service (installs all five packages,
checks the user, directories and units, runs `ascender-web migrate`, starts
the web server and checks `/api/v2/ping/` reports the version and `/docs/`
is served, starts the task process and checks it registers its node,
applies a bundle made on the spot with `ascender-node-apply-bundle` and
runs receptor with the result), then publishes a release and redeploys the
Pages site. A nightly run that finds its version published already stops.

Signing: with a repository secret `PACKAGING_GPG_PRIVATE_KEY` (an
ASCII-armoured private key without a passphrase) the `Release` files are
signed, the RPMs are signed, and the public key is published as `KEY.gpg`
and `KEY.asc`; the site's instructions change to match. Without it the
repositories are unsigned and the instructions say `trusted=yes` and
`gpgcheck=0`.

## Adopting this repository

Nothing here is tied to sol1 beyond defaults. The workflow serves the
site of whichever repository it runs in and names that repository as
the packages' homepage, so a fork, or a transfer to another organisation,
needs only:

1. GitHub Pages enabled for the repository with the source set to
   GitHub Actions (`gh api -X POST repos/OWNER/REPO/pages -f build_type=workflow`).
2. The signing key as the secret `PACKAGING_GPG_PRIVATE_KEY`, when the
   packages are to be signed; without it they are published unsigned.
3. Optionally the repository variables `PACKAGE_MAINTAINER` (`Name <address>`)
   and `PACKAGE_VENDOR`, which go into the package metadata and the apt
   `Origin`; unset, the defaults in `scripts/build-packages.sh` apply.
4. `source.env` pointed at the source to build.

Changes are welcome as pull requests, signed off as in Ascender's own
repository (`git commit -s`, the Developer Certificate of Origin).
`make test` runs what the workflow runs.

## Layout

    source.env            which Ascender to build
    nfpm/                 one package definition each
    packaging/systemd/    the units (web and task carry the version, rendered at build)
    packaging/scripts/    maintainer scripts (post-install, pre-remove)
    packaging/bin/        ascender-node-apply-bundle, setup-single-node, the subordinate id helper
    packaging/env/        the shipped ascender.env
    scripts/              build, version, release and repository scripts
    tests/                the smoke test and its local runner
    ansible/              the installer (next)
    nomad/                the Nomad jobs (next)

## Next

- An Ansible collection that installs these packages on an inventory of
  hosts and wires a cluster: PostgreSQL, web, control nodes with their
  receptor, execution and hop nodes, the mesh CA and work signing key, the
  register and address commands, the bundles. Nothing in it needs a change
  to Ascender.
- Enrolment from the node itself (`ascender-node enrol --server --token`)
  instead of a bundle download, which needs an endpoint in Ascender: a
  pull request upstream once the shape is proven here.
- Nomad job specifications for the same components.
- `ansible-runner` and, if EPEL's falls behind, receptor packages for EL.
- Tests on real virtual machines with systemd, podman and a job run.
