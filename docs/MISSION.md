# Mission: Learn OVN From Scratch

## Why
The user wants to learn OVN from first principles using the local OVN source tree and the interactive sandbox shell already created in this workspace. The goal is practical understanding: connect OVN concepts to real commands, database state, and eventually source code.

## Success looks like
- Explain the OVN control-plane flow from Northbound DB to Southbound DB to Open vSwitch.
- Build small logical topologies in `ovn/tutorial/sandbox` and inspect what changed.
- Use `ovn-nbctl`, `ovn-sbctl`, `ovn-trace`, `ovs-vsctl`, and `ovs-ofctl` without guessing what layer each command targets.
- Read relevant files under `ovn/` to connect observed behavior to implementation.

## Constraints
- Start from scratch.
- Prefer short, interactive lessons using the local sandbox.
- Use trusted local OVN documentation and source files as the main references.

## Out of scope
- Production OVN cluster operations until the core model is understood.
- Kubernetes-specific OVN-Kubernetes troubleshooting until the OVN basics are stable.
