# OVN Resources

## Knowledge

- [Local: OVN sandbox tutorial](ovn/Documentation/tutorials/ovn-sandbox.rst)
  The primary hands-on guide for this workspace. Use for sandbox commands, logical switch/router exercises, and `ovn-trace` practice.
- [Local: OVN architecture manual](ovn/ovn-architecture.7)
  The primary architecture source. Use for the control-plane model, Northbound/Southbound DB roles, `ovn-northd`, `ovn-controller`, and chassis concepts.
- [Local: OVN Northbound schema](ovn/ovn-nb.5)
  Use when learning CMS-facing objects: logical switches, logical routers, ports, ACLs, DHCP options, and NAT.
- [Local: OVN Southbound schema](ovn/ovn-sb.5)
  Use when learning compiled logical flows, port bindings, chassis state, and what `ovn-controller` consumes.
- [Local: `tutorial/ovn-setup.sh`](ovn/tutorial/ovn-setup.sh)
  Use as the smallest reproducible topology: two logical switches connected by one logical router.

## Wisdom (Communities)

- [OVN project mailing lists](https://www.ovn.org/en/support/)
  Best place to observe design discussions, ask implementation-level questions, and validate mental models against maintainers.
- [OVN GitHub repository](https://github.com/ovn-org/ovn)
  Use for issues, pull requests, and reading current implementation context around features.

## Gaps

- No user preference recorded yet for joining communities; default to local sandbox practice first.
