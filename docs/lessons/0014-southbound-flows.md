# Southbound Flows After Compilation

_Once `ovn-northd` compiles your NB intent it lands in the SB `Logical_Flow` table. This lesson shows what those rows are, how to look them up, and which ones you will meet again and again._

## The One Big Idea

A SB `Logical_Flow` row is one rule in one pipeline table of one logical datapath. It is the compiled form of NB intent, not the intent itself. You never write these rows by hand; `ovn-northd` generates them, and `ovn-controller` translates the relevant ones into OpenFlow on `br-int`.

- **NB**: Logical switch/router, ports, ACLs, NAT (intent)
- **northd**: compiles
- **SB**: `Logical_Flow` rows per datapath (the pipeline)
- **ovn-controller**: translates local flows
- **OpenFlow**: on `br-int` (the datapath)

A single row is: **{datapath, pipeline, table, priority, match, actions}**. Evaluation: enter at table 0, find true matches, the **highest priority** wins, run its actions; `next` advances to the next table, `output` delivers the packet.

## What "Compiled" Actually Means

You already know NB is a graph of logical objects. `ovn-northd` walks that graph and emits, for each datapath, a fixed sequence of numbered tables (the pipeline). Each rule becomes a `Logical_Flow` row. The row's stage name is stored by northd in `external_ids["stage-name"]`, which is the parenthetical you see in `ovn-sbctl lflow-list` output: `table=9 (ls_in_acl_eval)`.

| Column | Meaning |
|---|---|
| logical_datapath | Which logical switch or router this flow belongs to (or `logical_dp_group` for a group). |
| pipeline | `ingress` or `egress`. |
| table_id | The table number inside that pipeline (0..34 for switches, 0..28 for routers). |
| priority | Higher wins when several rules match (0..65535). |
| match | The condition, in OVN logical-field syntax (`inport`, `eth.dst`, `ip4.src`, `reg0[2]`, `ct.new`, `is_chassis_resident(...)`, ...). |
| actions | What to do: set fields, `next;`, `output(...)`, `ct_lb_mark(...)`, `ct_snat(...)`, `drop;`. |
| external_ids | Includes `stage-name` (the human table name) and often `stage-hint`. |
| tags / flow_desc / controller_meter | Metadata, descriptions, and logging meters. |

## How To Look Them Up

```sh
# all flows for one datapath (by name)
ovn-sbctl lflow-list sw0
ovn-sbctl lflow-list lr0

# every flow in the DB
ovn-sbctl lflow-list

# how many flows per table / datapath
ovn-sbctl count-flows sw0

# include the first 32 bits of each flow UUID (matches OpenFlow cookie)
ovn-sbctl --uuid lflow-list sw0

# show the local OpenFlow generated from each logical flow
ovn-sbctl --ovs lflow-list sw0
ovn-sbctl --ovs --stats lflow-list lr0

# also dump the SB records the flows are derived from (ports, MACs, LBs)
ovn-sbctl --vflows lflow-list sw0

# find one flow by UUID (e.g. recovered from an OpenFlow cookie)
ovn-sbctl lflow-list sw0 5c234a70
```

1. `lflow-list DATAPATH` filters to one logical datapath; the datapath can be a name or UUID.
2. `--uuid` prints the first 32 bits of the flow UUID, which `ovn-controller` sets as the OpenFlow *cookie* - that is how you jump from a local OpenFlow row back to its logical flow.
3. `--ovs` connects to `br-int` and prints the OpenFlow underneath each logical flow. Useful only for flows that are actually installed locally.
4. Filter with grep to isolate a stage: `ovn-sbctl lflow-list sw0 | grep ls_in_acl`.

> Companion tools: `ovn-trace` simulates a packet through these flows, and `ovn-detrace` maps a flow back to the NB object that produced it.

## Reading One Line

```text
table=9 (ls_in_acl_eval), priority=2001, match=(outport == @pg-web && ip4 && tcp && tcp.dst == 80), action=(next;)
```

1. `table=9` + `(ls_in_acl_eval)` - ingress ACL evaluation on a logical switch (the parenthetical is `external_ids["stage-name"]`).
2. `priority=2001` - beats a default-deny at 2000. Higher number wins.
3. `match=(...)` - destination port group `@pg-web`, IPv4, TCP, dport 80.
4. `action=(next;)` - continue to the next table (traffic allowed to proceed).

## The Stages You Will Actually Meet

These are the table names northd registers (from `northd.h`). Learn the bolded ones first - they explain 90% of what you debug.

### Logical switch - ingress (packet enters from a port)

| Table | Stage | What it does |
|---|---|---|
| 0 | ls_in_check_port_sec | Start here. Drop malformed/VLAN/multicast-source; begin port-security. |
| 1 | ls_in_apply_port_sec | Apply port security (allowed MAC/IP per port). |
| 5 | ls_in_pre_acl | Pre-ACL classification; decides whether traffic is stateful. |
| 6 | ls_in_pre_lb | Marks traffic for load balancing; sets the LB enable bit. |
| 7 | ls_in_pre_stateful | Sets up conntrack (DNAT/SNAT) before stateful stages. |
| 9 | ls_in_acl_eval | **ACL evaluation - where SecurityGroups / NetworkPolicy compile.** |
| 15 | ls_in_lb | Load-balancer DNAT of VIP traffic (`ct_lb_mark`). |
| 24 | ls_in_stateful | Commit conntrack / handle stateful ACLs. |
| 27 | ls_in_arp_rsp | Answer ARP/ND for router-owned addresses. |
| 28/29 | ls_in_dhcp_options / _response | DHCP respond when a port has DHCP options. |
| 30/31 | ls_in_dns_lookup / _response | DNS responder for the switch. |
| 33 | ls_in_l2_lkup | **L2 lookup / delivery decision - where `output(...)` fires.** |
| 34 | ls_in_l2_unknown | Flood unknown unicast/broadcast (or drop). |

### Logical switch - egress (packet leaves toward a port)

| Table | Stage | What it does |
|---|---|---|
| 2 | ls_out_pre_acl | Egress pre-classification. |
| 6 | ls_out_acl_eval | **Egress ACL evaluation.** |
| 12 | ls_out_stateful | Commit conntrack for egress. |
| 14/15 | ls_out_check/apply_port_sec | Port security on the way out. |

### Logical router - ingress (packet enters the router)

| Table | Stage | What it does |
|---|---|---|
| 0 | lr_in_admission | Start here. Validate the ingress port and L2/L3. |
| 3 | lr_in_ip_input | **Control plane: ARP, ND, ICMP to the router, TTL=0/1, TTL drop, IP options.** |
| 5 | lr_in_unsnat | Reverse SNAT for return traffic (`ct_snat;`). |
| 10 | lr_in_dnat | **DNAT / load-balancer VIP on the router.** |
| 16 | lr_in_ip_routing | **Routing decision - picks the outport from routes.** |
| 18 | lr_in_policy | Policy-based routing rules. |
| 22 | lr_in_arp_resolve | **Resolve next-hop MAC, rewrite `eth.src/eth.dst`.** |
| 25 | lr_in_gw_redirect | **Distributed gateway: send north-south traffic to the gateway chassis.** |
| 27 | lr_in_arp_request | Emit ARP requests for unresolved neighbors. |

### Logical router - egress (packet leaves the router)

| Table | Stage | What it does |
|---|---|---|
| 1 | lr_out_undnat | Reverse DNAT (return path of a VIP). |
| 3 | lr_out_snat | **SNAT / egress NAT (`ct_snat(EXTERNAL_IP)`).** |
| 6 | lr_out_delivery | Deliver the frame toward the resolved port. |

> Exact table numbers can shift between OVN versions. Trust the `stage-name` in parentheses, not the number, when reading output.

## Lab: Tour The Compiled Pipeline

```sh
./ovn-setup.sh

# see the whole switch pipeline start to finish
ovn-sbctl lflow-list sw0

# how many flows live in each table
ovn-sbctl count-flows sw0

# isolate the interesting stages
ovn-sbctl lflow-list sw0 | grep -E "ls_in_(check_port_sec|pre_acl|acl_eval|l2_lkup)"

# the router pipeline
ovn-sbctl lflow-list lr0 | grep -E "lr_in_(ip_input|ip_routing|arp_resolve)"

# jump from a logical flow to its OpenFlow
ovn-sbctl --uuid lflow-list sw0
ovn-sbctl --ovs lflow-list sw0
```

1. `lflow-list sw0` prints every table in order - this is the compiled switch pipeline.
2. `count-flows` is the fastest way to see how much is in each table (and whether a feature is absent because it produced no rows).
3. The greps show the tables responsible for port security, ACLs, delivery, routing, and neighbor resolution.
4. `--uuid` + `--ovs` connect the logical rows to the OpenFlow `ovn-controller` installed on `br-int`.

> Then simulate with `ovn-trace --minimal sw0 'inport == "sw0-port1" && ...'` and match each trace step to a table above. See [Reference 2](../reference/0002-ovn-trace-cheatsheet.md).

## Retrieval Check

Answer from memory before looking back.

Who writes the `Logical_Flow` rows into SB?

- ovn-controller installs them
- ovn-northd writes them
- the operator writes them

<details>
<summary>Answer</summary>

**ovn-northd writes them**

</details>

When multiple logical flows match, which one applies?

- lowest table wins
- first row listed wins
- highest priority wins

<details>
<summary>Answer</summary>

**highest priority wins**

</details>

What is `ls_in_l2_lkup` responsible for?

- where output fires
- where ACLs evaluate
- where ARP is answered

<details>
<summary>Answer</summary>

**where output fires**

</details>

Where does the parenthetical table name come from?

- the table_id number
- stage-name in external_ids
- the flow UUID

<details>
<summary>Answer</summary>

**stage-name in external_ids**

</details>

## Primary Sources

- [`ovn-logical-flows.7.rst`](../../ovn/Documentation/ref/ovn-logical-flows.7.rst) - the definitive description of every stage.
- [`northd.h`](../../ovn/northd/northd.h) - the PIPELINE_STAGE macro list (table numbers + `stage-name` strings).
- [`ovn-sbctl.8.xml`](../../ovn/utilities/ovn-sbctl.8.xml) - `lflow-list`, `--uuid`, `--ovs`, `--vflows`, `count-flows`.
- [`ovn-sb.5`](../../ovn/ovn-sb.5) - the `Logical_Flow` table columns.
- [`ovn-trace.8.xml`](../../ovn/utilities/ovn-trace.8.xml) - simulate a packet through these flows.

> Ask your agent-teacher to take one real `lflow-list` line and explain every field.

[← Lesson 13](0013-port-binding-lab.md) · [Lesson 3: Read a Logical Flow](0003-read-a-logical-flow.md) · [Logical Flow Reading Guide](../reference/0003-logical-flow-reading-guide.md) · [Course home](../README.md)
