# OVN Table Map

_Every table in the Northbound and Southbound databases, grouped by what it is for. Generated from the local `ovn-nb.ovsschema` / `ovn-sb.ovsschema`._

## The Two Databases

NB **Northbound** is the **intent** you write with `ovn-nbctl`: logical switches, routers, ports, ACLs, NAT, load balancers. It is a graph of logical objects.

SB **Southbound** is the **compiled reality**: `ovn-northd` turns NB intent into `Logical_Flow` rows; each `ovn-controller` reads them and binds real ports to `Chassis`. You read it with `ovn-sbctl`.

**Direction of truth:** NB is authoritative for *what you want*; SB is authoritative for *what is actually programmed and bound*. A row can exist in NB with no effect until northd compiles it and a chassis claims it.

## How To List Tables

Table names come from the schema. From the sandbox shell:

```text
ovsdb-client list-tables "$OVN_NB_DB" OVN_Northbound
ovsdb-client list-tables "$OVN_SB_DB" OVN_Southbound

# list every record in a table (no record name)
ovn-sbctl list Port_Binding
ovn-nbctl list Logical_Switch

# list the whole database (all tables)
ovn-nbctl list
```

Or read the schema files directly: `ovn/ovn-nb.ovsschema` and `ovn/ovn-sb.ovsschema`.

## Northbound Tables (38)

*Topology - the logical graph*

| Table | Holds |
|---|---|
| Logical_Switch | A logical L2 switch. Owns a set of ports and optional ACL/LB references. |
| Logical_Switch_Port | A port on a logical switch. Types: `""` (VIF), `router`, `localnet`, `virtual`. The name is the join key to SB and OVS. |
| Logical_Router | A logical L3 router. Owns ports, static routes, NAT rows, policies. |
| Logical_Router_Port | A port on a router (MAC + one or more `networks` = directly connected routes). |
| Logical_Router_Static_Route | An explicit `prefix -> next-hop` route on a router (added with `lr-route-add`). |
| Logical_Router_Policy | Policy-based routing: match on packet fields, then reroute/allow/drop. |

*Policy & security*

| Table | Holds |
|---|---|
| ACL | Allow/drop/reject rules attached to a Logical_Switch or a Port_Group. |
| Address_Set | A named set of IPs/MACs you can reference in ACL matches as `$name`. |
| Port_Group | A named set of switch ports, so one ACL applies to many ports. Referenced as `@name`. |
| QoS | Rate limiting / DSCP marking on switch traffic. |
| Copp | Control-plane protection: limit ARP/ND/ICMP sent to a logical router. |
| Meter / Meter_Band | Meters + bands used to rate-limit ACL logging. |
| Forwarding_Group | A set of ports sharing a virtual L2/L3 identity (active/standby "virtual port"). |

*Services: DHCP, DNS, load balancing, NAT*

| Table | Holds |
|---|---|
| DHCP_Options | A DHCP options template; a Logical_Switch_Port references it to get DHCP answers. |
| DHCP_Relay | Configuration to relay DHCP to external servers. |
| DNS | DNS records answered by the logical switch's DNS responder. |
| Load_Balancer | A VIP map: `VIP -> comma-separated backends`, one protocol per row. |
| Load_Balancer_Health_Check | Health-check config for LB backends. |
| Load_Balancer_Group | A group of load balancers applied together. |
| NAT | Source/destination NAT on a router: type `snat`, `dnat`, or `dnat_and_snat`. No name column - keyed by content. |
| Static_MAC_Binding | Pre-seeded IP↔MAC bindings so OVN skips ARP for known peers. |

*High availability & gateway*

| Table | Holds |
|---|---|
| Gateway_Chassis | Binds a chassis to a Logical_Router_Port, making it a distributed gateway port. Required for router NAT to be programmed. |
| HA_Chassis | One chassis entry inside an HA group, with priority. |
| HA_Chassis_Group | An ordered set of HA chassis for gateway failover. |
| BFD | BFD session config used for fast HA failover. |
| Chassis_Template_Var | Per-chassis variables substituted into templated options. |

*Observability & plumbing*

| Table | Holds |
|---|---|
| Mirror / Mirror_Rule | Port mirroring to a destination. |
| Sample / Sample_Collector / Sampling_App | IPFIX/flow sampling configuration. |
| Network_Function / Network_Function_Group / Network_Function_Health_Check | Offload of routing/network functions (newer feature) to smart NICs / DPUs. |
| NB_Global | Singleton: global NB options (e.g. `install_ls_lb_from_router`). |
| Connection / SSL | OVSDB server connection + SSL config (not logical objects). |

## Southbound Tables (41)

*Compiled topology & dataplane*

| Table | Holds |
|---|---|
| Datapath_Binding | One per logical datapath (a switch or router). Carries the `tunnel_key` used as datapath identity. |
| Logical_DP_Group | A group of datapaths (e.g. for shared multicast). |
| Logical_Flow | **The heart.** The compiled pipeline: table, priority, match, actions. This is what `ovn-sbctl lflow-list` prints. |
| Multicast_Group | Flooding group per logical switch (unknown unicast, broadcast, multicast). |
| Port_Binding | One per NB logical port. Binds `logical_port` to a `chassis`, carries `tunnel_key`, `mac`, `type`. |
| MAC_Binding | Learned IP↔MAC per datapath (the ARP/ND resolution cache). |
| FDB | Forwarding database for MAC learning on localnet/VTEP segments. |
| Static_MAC_Binding | Advertised/static MAC bindings. |
| ACL_ID | Links an ACL to its logical flow (for logging / conntrack labels). |
| ECMP_Nexthop | ECMP nexthop groups for multipath routes. |

*Chassis (physical nodes)*

| Table | Holds |
|---|---|
| Chassis | A transport node running `ovn-controller`; has `hostname`, `Encap` refs, and port bindings. |
| Chassis_Private | Per-chassis private state: `nb_cfg` version, hostname, BFD status. |
| Encap | A tunnel endpoint on a chassis (type `geneve`/`vxlan`/`stt` + IP). |
| Gateway_Chassis | SB copy of gateway chassis bindings. |
| HA_Chassis / HA_Chassis_Group | HA groups for gateway failover. |
| Chassis_Template_Var | Per-chassis template variables. |
| Controller_Event | Events reported by controllers (port up/down, etc.). |

*Mirrored tables (NB → SB copies used by flows)*

| Table | Holds |
|---|---|
| Address_Set | SB instance of address sets referenced by logical flows. |
| Port_Group | SB instance of port groups (with resolved port UUIDs). |
| Load_Balancer | SB instance of load balancers. |
| Service_Monitor | Per-backend service health state for load balancers. |
| DHCP_Options / DHCPv6_Options | SB DHCP option rows. |
| DNS | SB DNS rows. |
| Meter / Meter_Band | SB meters for ACL logging. |
| Mirror | SB mirroring rows. |
| BFD | BFD sessions between chassis. |

*Routing integration, multicast, plumbing*

| Table | Holds |
|---|---|
| Advertised_Route | Routes OVN advertises via dynamic routing (BGP). |
| Advertised_MAC_Binding | MAC bindings advertised outward. |
| Learned_Route | Routes learned from a routing protocol and installed into OVN. |
| IGMP_Group | IGMP multicast membership for a logical switch. |
| IP_Multicast | Multicast relay configuration. |
| RBAC_Permission / RBAC_Role | Role-based access control: restricts what each `ovn-controller` may write to SB. |
| SB_Global | Singleton: global SB options (e.g. `svc_monitor_mac`). |
| Connection / SSL | OVSDB server connection + SSL config (not logical objects). |

## The Tables You Actually Touch In The Sandbox

**NB:** Logical_Switch, Logical_Switch_Port, Logical_Router, Logical_Router_Port, Logical_Router_Static_Route, ACL, Address_Set, Port_Group, Load_Balancer, NAT, DHCP_Options, DNS.

**SB:** Datapath_Binding, Logical_Flow, Port_Binding, MAC_Binding, Chassis, Encap, Multicast_Group, Address_Set, Port_Group, Load_Balancer.

```sh
# the fastest way to see the interesting SB state
ovn-sbctl show
ovn-sbctl lflow-list sw0
ovn-sbctl list Port_Binding
ovn-sbctl list MAC_Binding
ovn-sbctl list Datapath_Binding
```

## Primary Sources

[ovn-nb.5](../../ovn/ovn-nb.5) - every Northbound table and column.

[ovn-sb.5](../../ovn/ovn-sb.5) - every Southbound table and column.

[ovn-architecture.7.xml](../../ovn/ovn-architecture.7.xml) - how NB intent becomes SB reality.

[ovn-logical-flows.7.rst](../../ovn/Documentation/ref/ovn-logical-flows.7.rst) - what the Logical_Flow rows mean.

[Back to the course](../README.md) · [Lesson 3: Read a Logical Flow](../lessons/0003-read-a-logical-flow.md) · [Logical Flow Reading Guide](0003-logical-flow-reading-guide.md)
