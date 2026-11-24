# Installer (planned)

An Ansible collection, `sol1.ascender`, that installs the packages this
repository builds on an inventory of hosts and wires them into a cluster:

- `postgres`: PostgreSQL for the control plane, or an external server's details;
- `web`: `ascender-web` behind a certificate;
- `control`: `ascender-task` as a control node (or hybrid on a single host),
  receptor beside it from a configuration the role writes (listener, work
  signing, TLS client), the mesh CA and the work signing key pair made once
  and copied to every control node;
- `execution` and `hop`: `ascender-node`, registered with
  `provision_instance` and `add_receptor_address` on a control node, a
  certificate signed by the mesh CA, `receptor.conf` written the way
  `ascender-node-apply-bundle` writes it.

Everything it does exists in Ascender today; no change upstream is needed.
Nothing here yet.
