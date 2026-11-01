# Port Binding Lab

_The hands-on version of Lesson 12. Build a router with a switch on each end, then drive binding by hand: create an OVS interface, watch SB stay empty, add `iface-id`, watch the chassis appear, then unbind it._

## The One Thing This Lab Proves

`ovn-controller` binds a port because a **local OVS interface** claims it with `external_ids:iface-id`. A local OVS port without `iface-id` binds nothing; the same port with `iface-id` binds instantly. SB only *records* the result in `Port_Binding.chassis`.

```text
NB Logical_Switch_Port name  ==  SB Port_Binding.logical_port  ==  OVS Interface.external_ids:iface-id
```

> Read [Lesson 12](0012-who-binds-a-port.md) first if the direction of this arrow is not yet obvious.

## Before You Start

Run inside the OVN sandbox shell. Ensure the baseline exists (the tutorial topology and one chassis).

```sh
./ovn-setup.sh
ovn-sbctl show
```

1. `./ovn-setup.sh` gives you `sw0`/`sw1`, router `lr0`, and the local OVS ports `p1`/`p2` that are already bound.
2. `ovn-sbctl show` proves a chassis exists. You should see `Chassis chassis-1 ... hostname: sandbox` with `Port_Binding sw0-port1` and `sw1-port1` already bound. That is your reference for “bound”.

## Step 1: Build A Two-Ended Router Topology

One router, a switch on each side, and one host port per switch. This gives you two unbound ports to play with.

```sh
ovn-nbctl --wait=sb --may-exist lr-add lab-rtr
ovn-nbctl --wait=sb lrp-add lab-rtr lab-l 00:00:00:00:aa:01 10.50.10.1/24
ovn-nbctl --wait=sb lrp-add lab-rtr lab-r 00:00:00:00:aa:02 10.50.20.1/24

ovn-nbctl --wait=sb --may-exist ls-add lab-left
ovn-nbctl --wait=sb lsp-add lab-left lab-left-rtr
ovn-nbctl lsp-set-type lab-left-rtr router
ovn-nbctl lsp-set-addresses lab-left-rtr 00:00:00:00:aa:01
ovn-nbctl lsp-set-options lab-left-rtr router-port=lab-l
ovn-nbctl --wait=sb lsp-add lab-left lab-host-a
ovn-nbctl lsp-set-addresses lab-host-a "02:00:00:00:00:0a 10.50.10.10"

ovn-nbctl --wait=sb --may-exist ls-add lab-right
ovn-nbctl --wait=sb lsp-add lab-right lab-right-rtr
ovn-nbctl lsp-set-type lab-right-rtr router
ovn-nbctl lsp-set-addresses lab-right-rtr 00:00:00:00:aa:02
ovn-nbctl lsp-set-options lab-right-rtr router-port=lab-r
ovn-nbctl --wait=sb lsp-add lab-right lab-host-b
ovn-nbctl lsp-set-addresses lab-host-b "02:00:00:00:00:0b 10.50.20.10"

ovn-nbctl show
```

1. The two `lrp-add` lines create router ports `lab-l` (10.50.10.1/24) and `lab-r` (10.50.20.1/24). Each gives a directly-connected route.
2. Each switch gets a `router`-type port whose address is the router port's MAC and whose `router-port` option names the LRP. That option is the L2↔L3 splice.
3. `lab-host-a`/`lab-host-b` are the VIF-style ports - the ones you will bind to OVS by hand.

## Step 2: Nothing Is Bound Yet

The host ports exist in NB and SB, but SB has no chassis for them.

```sh
ovn-sbctl --columns=logical_port,type,mac,chassis,up list Port_Binding lab-host-a
ovn-sbctl --columns=logical_port,type,mac,chassis,up list Port_Binding lab-host-b
```

**Expect:** `logical_port : lab-host-a`, `type : ""`, `chassis : []`, `up : false`. Empty `chassis` = unbound. Nothing local has claimed these names.

## Step 3: Create An OVS Port With No `iface-id`

Add a local OVS interface but do *not* tag it. This isolates the variable: a port alone is not a claim.

```sh
ovs-vsctl --may-exist add-port br-int lab-a
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding lab-host-a
```

**Expect:** `chassis : []` still. The OVS port exists (`ovs-vsctl show` lists `lab-a`) but `ovn-controller` ignores it because there is no `iface-id`.

## Step 4: Add `iface-id` - Watch It Bind

Now set the claim. In under a second the SB row fills in.

```sh
ovs-vsctl set Interface lab-a external_ids:iface-id=lab-host-a
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding lab-host-a
ovs-vsctl get Interface lab-a external_ids
```

**Expect:** `chassis : 8a5acdda-...` (the `chassis-1` UUID) and `up : true`. The interface now shows `ovn-installed="true"`. That is the bind.

The same two-step for the right side:

```sh
ovs-vsctl --may-exist add-port br-int lab-b
ovn-sbctl --columns=logical_port,chassis list Port_Binding lab-host-b
ovs-vsctl set Interface lab-b external_ids:iface-id=lab-host-b
ovn-sbctl --columns=logical_port,chassis list Port_Binding lab-host-b
ovn-sbctl show
```

**Expect:** `lab-host-b` goes from `chassis : []` to bound, and `ovn-sbctl show` now lists `Port_Binding lab-host-a` and `Port_Binding lab-host-b` under `Chassis chassis-1`.

## Step 5: Decode The OVS Tree

Confirm which interface belongs to which port, and where the claim lives.

```sh
ovs-vsctl show
ovs-vsctl get Port lab-a interfaces
ovs-vsctl get Interface lab-a ofport
ovs-vsctl get Interface lab-a external_ids
ovs-vsctl list-br
```

1. `Bridge br-int` contains ports; each `Port` contains an `Interface`. See [Bridge / Port / Interface](../reference/0009-ovs-bridge-port-interface.md) for the full decoding.
2. `ofport` is the local OpenFlow port number OVN programs flows against.
3. `external_ids:iface-id` is the claim that produced the SB `chassis` field.

## Step 6: Unbind Correctly

Binding follows the local interface. So unbinding means removing the claim, not poking SB.

```sh
ovs-vsctl remove Interface lab-a external_ids iface-id
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding lab-host-a

# re-claim it
ovs-vsctl set Interface lab-a external_ids:iface-id=lab-host-a
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding lab-host-a
```

**Expect:** removing the `iface-id` drops `chassis` back to `[]`; re-adding it rebinds. A plain `ovn-sbctl lsp-unbind` is *temporary* here - the controller immediately reclaims because `lab-a` still claims the port:

```sh
ovn-sbctl lsp-unbind lab-host-a      # empty for a moment...
ovn-sbctl --columns=logical_port,chassis list Port_Binding lab-host-a   # ...then bound again
```

## Step 7: The Manual Bind (When No Local Port Exists)

Remove the local interface entirely, then force the binding from SB. With nothing competing, it sticks.

```sh
ovs-vsctl --if-exists del-port br-int lab-a
ovn-sbctl lsp-bind lab-host-a chassis-1
ovn-sbctl --columns=logical_port,chassis list Port_Binding lab-host-a
ovn-sbctl lsp-unbind lab-host-a
```

1. With no OVS interface carrying `iface-id=lab-host-a`, `lsp-bind` holds.
2. Re-create the interface (`add-port` + `set ... iface-id`) and the controller takes back over.
3. This is why `lsp-bind` is a debug/edge tool, not the normal path.

## Step 8: Cleanup

```sh
ovs-vsctl --if-exists del-port br-int lab-a
ovs-vsctl --if-exists del-port br-int lab-b
ovn-nbctl --if-exists lr-del lab-rtr
ovn-nbctl --if-exists ls-del lab-left
ovn-nbctl --if-exists ls-del lab-right
```

1. Delete the local OVS ports first (release the claims).
2. Deleting the router and switches removes the logical objects; `ovn-northd` removes the SB rows automatically.

## State Reference

| Action | NB LSP | SB Port_Binding.chassis | OVS Interface.iface-id |
|---|---|---|---|
| NB port created | exists | `[]` | absent |
| OVS port added, no id | exists | `[]` | absent |
| `iface-id` set | exists | chassis UUID | `=<port>` |
| `iface-id` removed | exists | `[]` | absent |
| manual `lsp-bind` | exists | chassis UUID | absent (forced) |

## Retrieval Check

Answer from memory before looking back.

At which point does `ovn-controller` bind the port?

- when the OVS port exists
- when iface-id is set
- when NB intent is made

<details>
<summary>Answer</summary>

**when iface-id is set**

</details>

What actually unbinds a port that has a local OVS interface?

- remove the iface-id
- run lsp-unbind once
- delete the switch row

<details>
<summary>Answer</summary>

**remove the iface-id**

</details>

What does the controller do the moment it discovers a claim?

- creates the OVS port
- edits the NB port
- writes chassis into SB

<details>
<summary>Answer</summary>

**writes chassis into SB**

</details>

What is SB `Port_Binding.chassis`?

- an instruction to OVS
- SB records the result
- a local device name

<details>
<summary>Answer</summary>

**SB records the result**

</details>

## Next And Sources

- [Lesson 12: Who Binds A Port?](0012-who-binds-a-port.md) - the concept behind this lab.
- [Reference 9: Bridge / Port / Interface](../reference/0009-ovs-bridge-port-interface.md) - decode the OVS tree.
- [Reference 6: Port Binding Map](../reference/0006-port-binding-map.md) - the join key across the three layers.
- [ovn-controller.8.xml](../../ovn/controller/ovn-controller.8.xml) - the local agent that performs the bind.

> Ask your agent-teacher to trace one of these ports across NB, SB, and OVS in your own sandbox.

[← Lesson 12](0012-who-binds-a-port.md) · [Lesson 14: Southbound Flows →](0014-southbound-flows.md) · [Course home](../README.md)
