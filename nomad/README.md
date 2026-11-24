# Nomad jobs (planned)

Job specifications running the same components under Nomad: a `web` group
scaled behind the Nomad service mesh, a `control` group with `ascender-task`
and a receptor sidecar, execution nodes as a system job that enrols at
prestart, PostgreSQL optional. They can run the upstream images or the
packages' binaries. Nothing here yet.
