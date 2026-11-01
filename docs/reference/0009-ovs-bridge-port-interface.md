# OVS: Bridge, Port, Interface

_What the `ovs-vsctl show` tree actually means. Three different rows, three different jobs - a common source of confusion._

## The Hierarchy

The OVS database (`Open_vSwitch`) contains bridges. Each bridge contains ports. Each port contains one or more interfaces.

Open_vSwitch (the OVS database / daemon) └── Bridge br-int # an L2 switch (one broadcast domain) ├── Port br-int │ └── Interface br-int # type internal (the bridge's own port) ├── Port p1 │ └── Interface p1 # a real device on the bridge └── Port who-if └── Interface who-if

> In the common 1-interface-per-port case, the Port and its Interface carry the **same name** - which is why `ovs-vsctl show` looks like it repeats itself. They are still two separate rows.

## Who Does What

| Row | What it is | Key columns |
|---|---|---|
| Bridge   br-int | An L2 switch - one forwarding domain with one flow table. Has a `fail_mode` (`secure` = controlled by OpenFlow, no fallback; `standalone` = acts like a normal L2 switch). | `fail_mode`, `datapath_type`, `ports` |
| Port | A logical attachment point on a bridge. Owns VLAN config and bundles one or more interfaces. A port belongs to *exactly one* bridge. | `name`, `interfaces`, `tag`, `trunks`, `vlan_mode` |
| Interface | The actual network device - the thing that has a name, a type, a MAC, and an `ofport`. This is where `external_ids:iface-id` lives. | `name`, `type`, `ofport`, `mac_in_use`, `external_ids` |

Cardinality: `1 Bridge : N Ports`, and `1 Port : N Interfaces` (usually 1; bonding/LAG uses several interfaces under one port).

## Interface `type` - What You Will Actually See

| type | Meaning |
|---|---|
| internal | A software port that represents the bridge itself; can carry an IP. This is why `br-int` appears as both a Bridge and a Port/Interface. |
| system | A real Linux netdev (veth, tap, physical NIC) attached to the bridge. |
| patch | A virtual wire between two bridges; carries `options:peer=<other-interface>`. Used to connect `br-int` to a provider bridge. |
| geneve / vxlan / stt | A tunnel to another chassis, created by `ovn-controller` (e.g. `ovn-<chassis>-0`). |

## Reading Your Sandbox Output

```text
394adb5d-...                      # the Open_vSwitch row UUID
    Bridge br-int                 # one L2 switch
        fail_mode: secure         # OVN controls it; no NORMAL fallback
        datapath_type: system     # kernel datapath
        Port br-int               # the bridge's own port
            Interface br-int
                type: internal
        Port pb
            Interface pb         # a plain local device (no type = system)
        Port p1
            Interface p1         # tutorial's sw0-port1 leg (iface-id=sw0-port1)
        Port who-if
            Interface who-if     # your lesson port (iface-id=who-port)
        Port p2
            Interface p2         # tutorial's sw1-port1 leg
        Port pa
            Interface pa         # your lesson port (iface-id=hostA)
```

Note there are no tunnel ports listed here because the sandbox has a single chassis (nothing to tunnel to). On a multi-node cluster you would also see `Port ovn-<remote>-0` with `Interface ... type: geneve`.

## Commands To Inspect Each Level

```sh
# bridges
ovs-vsctl list-br
ovs-vsctl show

# ports on a bridge
ovs-vsctl list-ports br-int
ovs-vsctl get Bridge br-int ports

# interfaces under a port
ovs-vsctl get Port p1 interfaces
ovs-vsctl list Interface
ovs-vsctl --columns=name,type,ofport,external_ids list Interface

# the OpenFlow port number OpenFlow rules use
ovs-vsctl get Interface p1 ofport
ovs-ofctl show br-int
```

## Why It Matters For OVN

- OVN binds on the **Interface**: `Interface.external_ids:iface-id` is the join key (see Lesson 12).
- VLAN config lives on the **Port** (`tag`/`trunks`), not the Interface.
- Bridge `fail_mode` decides behavior when no OpenFlow matches: `secure` drops (integration bridge), `standalone` does normal L2 (provider/host bridges).
- `ovn-controller` programs OpenFlow onto the bridge (`br-int`) using interface `ofport` numbers, not names.

## Primary Sources

[ovs-vswitchd.conf.db.5](../../ovn/ovs/vswitchd/ovs-vswitchd.conf.db.5) - the `Bridge`, `Port`, and `Interface` tables and every column.

[ovs-vsctl.8](../../ovn/ovs/utilities/ovs-vsctl.8) - `list-br`, `list-ports`, `show`, and friends.

[Lesson 4: Find Local OpenFlow](../lessons/0004-find-local-openflow.md) · [Local OVS OpenFlow Map](0004-local-ovs-openflow-map.md) · [Lesson 12: Who Binds A Port?](../lessons/0012-who-binds-a-port.md)
