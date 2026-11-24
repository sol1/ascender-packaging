#!/bin/sh
# Installs the packages from /packages (deb/ or rpm/) in this container and
# checks them: the user and directories, the units, the web server against
# the database the environment names (PGHOST, PGPORT, PGUSER, PGPASSWORD,
# PGDATABASE), the task process registering its node, and the node package
# applying a bundle made here and running receptor with it. VERSION is the
# version the server must report. Runs as root in a Debian 13 or Rocky
# Linux 9 container without systemd (the workflow and tests/run-local.sh).
set -eux
: "${VERSION:?}" "${PGHOST:?}"
export PGPORT=${PGPORT:-5432} PGUSER=${PGUSER:-ascender} PGPASSWORD=${PGPASSWORD:-ascender} PGDATABASE=${PGDATABASE:-ascender}
# (os-release has a VERSION of its own: only ID is wanted)
ID=$(. /etc/os-release && echo "$ID")
case $ID in
debian | ubuntu)
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends systemd curl openssl python3 util-linux >/dev/null
	apt-get install -y -qq --no-install-recommends /packages/deb/ascender-common_*_all.deb /packages/deb/ascender-web_*_amd64.deb /packages/deb/ascender-task_*_amd64.deb /packages/deb/ascender-node_*_all.deb /packages/deb/ascender_*_all.deb >/dev/null
	rpm_or_dpkg="dpkg -l"
	;;
*)
	dnf install -y -q epel-release >/dev/null
	dnf install -y -q systemd openssl python3 util-linux receptorctl >/dev/null
	dnf install -y -q /packages/rpm/ascender-common-*.noarch.rpm /packages/rpm/ascender-web-*.x86_64.rpm /packages/rpm/ascender-task-*.x86_64.rpm /packages/rpm/ascender-node-*.noarch.rpm /packages/rpm/ascender-*.noarch.rpm >/dev/null
	rpm_or_dpkg="rpm -qa"
	;;
esac
$rpm_or_dpkg | grep -E '^(ii +)?ascender' || $rpm_or_dpkg | grep ascender

# The user, the subordinate ids, the directories.
id ascender
grep -q '^ascender:' /etc/subuid && grep -q '^ascender:' /etc/subgid
[ "$(stat -c %U:%G /var/lib/ascender)" = ascender:ascender ]
[ "$(stat -c %U:%G:%a /etc/ascender)" = root:ascender:750 ]
[ "$(stat -c %U:%G:%a /etc/ascender/ascender.env)" = root:ascender:640 ]
# The single-node setup wrote the secrets (without systemd it stops there).
[ -s /etc/ascender/SECRET_KEY ] && [ -s /etc/ascender/ADMIN_PASSWORD ] && [ -s /etc/ascender/tls/server.crt ]
grep -q '^ASCENDER_DATABASE_URL=' /etc/ascender/ascender.env
# The units parse, and carry the version.
systemd-analyze verify /usr/lib/systemd/system/ascender-web.service /usr/lib/systemd/system/ascender-task.service /usr/lib/systemd/system/ascender-node.service 2>&1 | grep -vE 'Failed to (open|connect)|dbus|Cannot (open|resolve)|not found: No such file' || true
grep -q "ASCENDER_VERSION=$VERSION" /usr/lib/systemd/system/ascender-web.service
grep -q "ASCENDER_VERSION=$VERSION" /usr/lib/systemd/system/ascender-task.service
ascender-web --help | head -3
ascender-task --help 2>&1 | head -1 || true

# The web server against the database, as the service runs it (user, environment).
run_as() { # the unit's environment, as far as it is a file: ascender.env on top of the defaults
	runuser -u ascender -- env \
		ASCENDER_VERSION="$VERSION" ASCENDER_DOCS_DIR=/usr/share/ascender/docs \
		ASCENDER_SECRET_KEY_FILE=/etc/ascender/SECRET_KEY ASCENDER_ADMIN_PASSWORD_FILE=/etc/ascender/ADMIN_PASSWORD \
		ASCENDER_RECEPTOR_DIR=/etc/ascender/receptor ASCENDER_RECEPTOR_CONFIG=/etc/ascender/receptor/receptor.conf \
		ASCENDER_DATABASE_URL="postgres://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable" \
		ASCENDER_LISTEN=127.0.0.1:8070 ASCENDER_MODE=development \
		HOME=/var/lib/ascender XDG_RUNTIME_DIR=/tmp/ascender-run ASCENDER_CONTAINER_RUNTIME=podman CONTAINERS_CONF=/etc/ascender/containers.conf \
		ASCENDER_CLUSTER_HOST_ID=smoke-node "$@"
}
mkdir -p /tmp/ascender-run && chown ascender /tmp/ascender-run
run_as ascender-web migrate
run_as ascender-web >/tmp/web.log 2>&1 &
for _ in $(seq 1 60); do
	curl -fsS http://127.0.0.1:8070/api/v2/ping/ >/tmp/ping.json 2>/dev/null && break
	sleep 1
done
cat /tmp/ping.json; echo
python3 -c "import json,sys; d=json.load(open('/tmp/ping.json')); assert d['version'] == sys.argv[1], d['version']" "$VERSION"
# The documentation site is served from the package.
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8070/docs/ | grep -q 200
# The admin password from the file works for the API.
curl -fsS -u "admin:$(cat /etc/ascender/ADMIN_PASSWORD)" http://127.0.0.1:8070/api/v2/me/ | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['results'][0]['username'] == 'admin'"

# The task process registers this node (podman has no nested containers here, so it may not become ready: the instance row is the check).
run_as ascender-task >/tmp/task.log 2>&1 &
for _ in $(seq 1 60); do
	curl -fsS -u "admin:$(cat /etc/ascender/ADMIN_PASSWORD)" http://127.0.0.1:8070/api/v2/instances/ 2>/dev/null | grep -q '"hostname":"smoke-node"' && break
	sleep 1
done
curl -fsS -u "admin:$(cat /etc/ascender/ADMIN_PASSWORD)" http://127.0.0.1:8070/api/v2/instances/ | python3 -c "import json,sys; d=json.load(sys.stdin); n=[i for i in d['results'] if i['hostname']=='smoke-node']; assert n, d; print('instance', n[0]['hostname'], n[0]['node_type'], n[0]['node_state'])"
grep -iE 'level=(error|fatal)' /tmp/web.log /tmp/task.log || true

# The node package: a bundle as Ascender makes one, with a CA made here, applied and run by receptor.
tmp=$(mktemp -d)
b=$tmp/exec1_install_bundle
mkdir -p "$b/receptor/tls/ca" "$b/group_vars"
openssl req -x509 -newkey rsa:2048 -nodes -days 7 -subj /CN=mesh-CA -keyout "$tmp/ca.key" -out "$b/receptor/tls/ca/mesh-CA.crt" 2>/dev/null
# Receptor wants its node id in the certificate, as the otherName Ascender's bundles carry.
openssl req -newkey rsa:2048 -nodes -subj /CN=exec1 -keyout "$b/receptor/tls/receptor.key" -out "$tmp/node.csr" 2>/dev/null
printf 'subjectAltName=DNS:exec1,otherName:1.3.6.1.4.1.2312.19.1;UTF8:exec1\n' >"$tmp/san.cnf"
openssl x509 -req -in "$tmp/node.csr" -CA "$b/receptor/tls/ca/mesh-CA.crt" -CAkey "$tmp/ca.key" -CAcreateserial -days 7 -extfile "$tmp/san.cnf" -out "$b/receptor/tls/receptor.crt" 2>/dev/null
openssl genrsa -out "$tmp/work.key" 2048 2>/dev/null && openssl rsa -in "$tmp/work.key" -pubout -out "$b/receptor/work_public_key.pem" 2>/dev/null
cat >"$b/group_vars/all.yml" <<'EOF'
receptor_user: awx
receptor_group: awx
receptor_verify: true
receptor_tls: true
receptor_mintls13: false
receptor_work_commands:
  ansible-runner:
    command: ansible-runner
    params: worker
    allowruntimeparams: true
    verifysignature: true
additional_python_packages:
  - ansible-runner
custom_worksign_public_keyfile: receptor/work_public_key.pem
custom_tls_certfile: receptor/tls/receptor.crt
custom_tls_keyfile: receptor/tls/receptor.key
custom_ca_certfile: receptor/tls/ca/mesh-CA.crt
receptor_protocol: tcp
receptor_listener: true
receptor_port: 27199
receptor_peers:
  - address: control.example.com:27199
    protocol: tcp
podman_user: "{{ receptor_user }}"
podman_group: "{{ receptor_group }}"
EOF
tar -C "$tmp" -czf "$tmp/bundle.tar.gz" exec1_install_bundle
ascender-node-apply-bundle --no-restart "$tmp/bundle.tar.gz"
cat /etc/ascender/receptor/receptor.conf
[ "$(stat -c %U:%G:%a /etc/ascender/receptor/tls/receptor.key)" = root:ascender:640 ]
mkdir -p /run/receptor && chown ascender /run/receptor
runuser -u ascender -- receptor -c /etc/ascender/receptor/receptor.conf >/tmp/receptor.log 2>&1 &
for _ in $(seq 1 30); do
	[ -S /run/receptor/receptor.sock ] && break
	sleep 1
done
[ -S /run/receptor/receptor.sock ] || { cat /tmp/receptor.log; exit 1; }
runuser -u ascender -- receptorctl --socket /run/receptor/receptor.sock status | tee /tmp/status.txt
grep -q 'exec1' /tmp/status.txt
grep -q 'ansible-runner' /tmp/status.txt
echo "smoke test passed: $ID, $VERSION"
