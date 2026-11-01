# OVN Resources

## Knowledge

- [Local: OVN sandbox tutorial](../ovn/Documentation/tutorials/ovn-sandbox.rst)
  The primary hands-on guide for this workspace. Use for sandbox commands, logical switch/router exercises, and `ovn-trace` practice.
- [Local: OVN architecture manual](../ovn/ovn-architecture.7)
  The primary architecture source. Use for the control-plane model, Northbound/Southbound DB roles, `ovn-northd`, `ovn-controller`, and chassis concepts.
- [Local: OVN Northbound schema](../ovn/ovn-nb.5)
  Use when learning CMS-facing objects: logical switches, logical routers, ports, ACLs, DHCP options, and NAT.
- [Local: OVN Southbound schema](../ovn/ovn-sb.5)
  Use when learning compiled logical flows, port bindings, chassis state, and what `ovn-controller` consumes.
- [Local: `tutorial/ovn-setup.sh`](../ovn/tutorial/ovn-setup.sh)
  Use as the smallest reproducible topology: two logical switches connected by one logical router.

## Command Manuals

One manual per surface from Lesson 1. Inside the sandbox shell, `man ovn-nbctl` (and the others) also works, since `ovn-sandbox` sets `MANPATH`.

| Tool | Surface | Online | Local source |
|---|---|---|---|
| `ovn-nbctl` | Northbound intent | [ovn-nbctl(8)](https://www.ovn.org/support/dist-docs/ovn-nbctl.8.html) | [`ovn/utilities/ovn-nbctl.8.xml`](../ovn/utilities/ovn-nbctl.8.xml) |
| `ovn-sbctl` | Southbound compiled state | [ovn-sbctl(8)](https://www.ovn.org/support/dist-docs/ovn-sbctl.8.html) | [`ovn/utilities/ovn-sbctl.8.xml`](../ovn/utilities/ovn-sbctl.8.xml) |
| `ovs-vsctl` | Local OVS configuration | [ovs-vsctl(8)](https://www.openvswitch.org/support/dist-docs/ovs-vsctl.8.txt) | [`ovn/ovs/utilities/ovs-vsctl.8.in`](../ovn/ovs/utilities/ovs-vsctl.8.in) |

The online pages track the latest release; the local files match the pinned `ovn/` commit you actually run.

## Wisdom (Communities)

- [OVN project mailing lists](https://www.ovn.org/en/support/)
  Best place to observe design discussions, ask implementation-level questions, and validate mental models against maintainers.
- [OVN GitHub repository](https://github.com/ovn-org/ovn)
  Use for issues, pull requests, and reading current implementation context around features.

## Gaps

- No user preference recorded yet for joining communities; default to local sandbox practice first.
