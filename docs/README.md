# Learn OVN

Short, command-driven lessons for learning OVN from scratch, using the local `ovn/` checkout and the sandbox started with `../sandbox.sh`.

Start with [MISSION.md](MISSION.md) for the goal, then work through the lessons in order with the reference pages open next to them.

## Getting started

`ovn/` is a git submodule pinned to an upstream OVN commit, so clone with submodules:

```sh
git clone --recurse-submodules <this-repo-url> learn-ovn
# or, in an existing clone
git submodule update --init ovn
```

If you forget, `sandbox.sh` fetches `ovn/` for you. It also fetches the nested `ovn/ovs` submodule, checks for build tools, and builds both:

```sh
./sandbox.sh          # build OVS + OVN if needed, then open the sandbox shell
./sandbox.sh cleanup  # stop sandbox daemons and remove ovn/tutorial/sandbox
```

## Lessons

| # | Lesson | Goal |
|---|---|---|
| 1 | [Find The Three Surfaces](lessons/0001-find-the-three-surfaces.md) | Tell NB intent, SB compiled state, and local OVS apart. |
| 2 | [Trace One Packet](lessons/0002-trace-one-packet.md) | Predict what OVN does to a packet with `ovn-trace`. |
| 3 | [Read A Logical Flow](lessons/0003-read-a-logical-flow.md) | Read the SB rules `ovn-trace` walks through. |
| 4 | [Find Local OpenFlow](lessons/0004-find-local-openflow.md) | Separate logical flows from local OpenFlow. |
| 5 | [Add One ACL](lessons/0005-add-one-acl.md) | Change NB intent and follow it into flows and traces. |
| 6 | [Follow a Port Binding](lessons/0006-follow-a-port-binding.md) | Map a logical port to the OVS interface that realizes it. |
| 7 | [Read Router Ports](lessons/0007-read-router-ports.md) | Predict the router output port from the destination IP. |
| 8 | [Kube-OVN CRDs to OVN](lessons/0008-kube-ovn-crds-to-ovn.md) | Rebuild Kube-OVN objects by hand in the sandbox. |
| 9 | [OpenStack Neutron to OVN](lessons/0009-openstack-to-ovn.md) | Rebuild Neutron ML2/OVN objects by hand in the sandbox. |
| 10 | [Kube-OVN vs OpenStack OVN](lessons/0010-kubeovn-vs-openstack-ovn.md) | Compare two real OVN integrations. |
| 11 | [NB to SB to OVS Port Binding](lessons/0011-nb-sb-ovs-port-binding.md) | Create a port, see it compiled, claim it with `iface-id`. |
| 12 | [Who Binds A Port?](lessons/0012-who-binds-a-port.md) | Learn which way the binding arrow points. |
| 13 | [Port Binding Lab](lessons/0013-port-binding-lab.md) | Bind and unbind ports by hand. |
| 14 | [Southbound Flows After Compilation](lessons/0014-southbound-flows.md) | Read and look up SB `Logical_Flow` rows. |

## Reference

1. [OVN Control Plane Map](reference/0001-ovn-control-plane-map.md)
2. [`ovn-trace` Cheatsheet](reference/0002-ovn-trace-cheatsheet.md)
3. [Logical Flow Reading Guide](reference/0003-logical-flow-reading-guide.md)
4. [Local OVS and OpenFlow Map](reference/0004-local-ovs-openflow-map.md)
5. [ACL Observation Loop](reference/0005-acl-observation-loop.md)
6. [Port Binding Map](reference/0006-port-binding-map.md)
7. [Router Port Routing Map](reference/0007-router-port-routing-map.md)
8. [OVN Table Map](reference/0008-ovn-table-map.md)
9. [OVS: Bridge, Port, Interface](reference/0009-ovs-bridge-port-interface.md)

Long form: [OVN/OVS Engineering Handbook](handbook.md), with OpenStack ML2/OVN, troubleshooting, and a glossary.

## Course notes

- [MISSION.md](MISSION.md): why and what success looks like
- [NOTES.md](NOTES.md): teaching notes
- [RESOURCES.md](RESOURCES.md): primary sources
- [learning-records/](learning-records/): what has been learned so far
