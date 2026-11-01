# NB Creation -> SB Port_Binding -> OVS Reality

_Create one logical port by hand, watch `ovn-northd` compile it into a Southbound `Port_Binding`, then make local OVS claim it with `external_ids:iface-id`._

## The One Big Idea

Creating a port in the Northbound DB does **not** automatically mean there is a Linux or OVS interface carrying packets. Northbound creation says “this logical attachment should exist.” Southbound `Port_Binding` says “OVN has compiled a runtime binding record for that logical attachment.” Local OVS only becomes involved when an OVS `Interface` claims the logical port name with `external_ids:iface-id`.

- **1. NB intent**: `Logical_Switch_Port bind-port`  
Created by `ovn-nbctl lsp-add`.
- **2. SB runtime row**: `Port_Binding logical_port=bind-port`  
Created by `ovn-northd`.
- **3. Local OVS claim**: `Interface bind-if external_ids:iface-id=bind-port`  
Seen by `ovn-controller`.

> The join key is the exact string `bind-port`. In OpenStack, this is normally the Neutron port UUID.

## Before You Start

Run inside the OVN sandbox shell. If the sandbox is fresh, create the tutorial topology first.

```sh
./ovn-setup.sh
```

1. `./ovn-setup.sh` creates the baseline sandbox objects: `sw0`, `sw1`, `lr0`, logical ports, and local OVS interfaces `p1`/`p2`. This lesson creates separate objects named `bind-*`.

## Step 1: Create Northbound Intent

Create a new logical switch and a logical switch port. At this point, you have only expressed OVN intent.

```sh
ovn-nbctl --wait=sb --may-exist ls-add bind-ls
ovn-nbctl --wait=sb --may-exist lsp-add bind-ls bind-port
ovn-nbctl --wait=sb lsp-set-addresses bind-port "50:54:00:00:30:10 10.30.0.10"
ovn-nbctl list Logical_Switch_Port bind-port
```

1. `ovn-nbctl --wait=sb --may-exist ls-add bind-ls` creates a Northbound `Logical_Switch`. `--wait=sb` waits until `ovn-northd` has propagated the transaction into Southbound.
2. `ovn-nbctl --wait=sb --may-exist lsp-add bind-ls bind-port` creates a Northbound `Logical_Switch_Port` named `bind-port` on that switch.
3. `ovn-nbctl --wait=sb lsp-set-addresses ...` gives the logical port a MAC/IP tuple. OVN uses this for logical L2 delivery and port security-style matching.
4. `ovn-nbctl list Logical_Switch_Port bind-port` prints the NB row. This is the intent layer: it says the logical port should exist, but not where it runs.

## Step 2: Observe the Southbound Port_Binding

Because `ovn-northd` saw the NB logical port, it creates a Southbound `Port_Binding`. Before local OVS claims the port, it should exist but be unbound.

```sh
ovn-sbctl --columns=logical_port,type,mac,chassis,datapath list Port_Binding bind-port
```

1. `logical_port` should be `bind-port`. This is the same join key from the NB logical switch port.
2. `type` should usually be empty for a normal VM/VIF-style logical port. Router ports, localnet ports, virtual ports, and other special ports have meaningful types.
3. `mac` should include the MAC/IP tuple you set in NB.
4. `datapath` points to the Southbound logical datapath generated for `bind-ls`.
5. `chassis` is the crucial field. Before local OVS claims the port, a normal unbound port commonly shows `[]`.

> This is why `Port_Binding` is so important in production. It is where you distinguish “Neutron/OVN created the port” from “a real chassis has claimed the port.”

## Step 3: Confirm OVS Has Not Claimed It Yet

Search local OVS for an interface whose `iface-id` is `bind-port`. Before you create one, there should be no local claim.

```sh
ovs-vsctl --columns=name,ofport,external_ids list Interface | grep -A2 -B1 bind-port || true
```

1. `ovs-vsctl --columns=... list Interface` prints local OVS interfaces.
2. `grep ... bind-port || true` filters for the logical port name while keeping the command from failing noisily if nothing matches.
3. If nothing appears, that is expected: the logical port exists in OVN, but no local OVS interface has claimed it.

## Step 4: Make Local OVS Claim the Logical Port

Now create a local OVS interface on `br-int` and set its `external_ids:iface-id` to the logical port name. This is the same mechanism Nova uses for VM tap interfaces in OpenStack, except Nova creates real VM interfaces instead of this simple sandbox port.

```sh
ovs-vsctl --may-exist add-port br-int bind-if -- set Interface bind-if external_ids:iface-id=bind-port
ovs-vsctl get Interface bind-if external_ids:iface-id
ovs-vsctl get Interface bind-if ofport
```

1. `ovs-vsctl --may-exist add-port br-int bind-if` creates a local OVS port/interface named `bind-if` on the integration bridge.
2. `set Interface bind-if external_ids:iface-id=bind-port` is the binding claim. It says: this local OVS interface realizes the OVN logical port named `bind-port`.
3. `ovs-vsctl get Interface bind-if external_ids:iface-id` verifies the join key from the OVS side.
4. `ovs-vsctl get Interface bind-if ofport` shows the OpenFlow port number OVS assigned locally. OpenFlow rules use this numeric `ofport`, not the logical name.

## Step 5: Watch Port_Binding Become Bound

After `ovn-controller` notices the OVS interface, it updates the Southbound `Port_Binding` with this chassis. If the field is still empty, run the command again after a moment.

```sh
ovn-sbctl --columns=logical_port,type,mac,chassis,datapath list Port_Binding bind-port
ovn-sbctl show
```

1. `ovn-sbctl ... list Port_Binding bind-port` should now show a non-empty `chassis` field. That is the moment the logical port becomes bound to this sandbox chassis.
2. `ovn-sbctl show` gives a compact chassis/datapath/port view. Look for `bind-port` under the chassis or related logical structure.

| State | NB Logical_Switch_Port | SB Port_Binding | OVS Interface |
|---|---|---|---|
| Created but unbound | Exists | Exists, `chassis=[]` | No matching `iface-id` |
| Bound locally | Exists | Exists, `chassis=[...]` | `external_ids:iface-id=bind-port` |
| OVS port deleted | Still exists | Usually returns to unbound | No matching interface |

## Step 6: See How It Looks in OVS/OpenFlow

OVS does not primarily show “Logical_Switch_Port bind-port” inside OpenFlow. It shows a local interface, an `ofport`, registers, metadata, and OpenFlow tables generated by `ovn-controller`. The logical name is easiest to see in OVSDB; OpenFlow uses compiled local representation.

```sh
ovs-vsctl list Interface bind-if
ovs-ofctl show br-int
ovs-ofctl dump-flows br-int | grep "in_port=$(ovs-vsctl get Interface bind-if ofport)" || true
ovn-sbctl --ovs lflow-list bind-ls
```

1. `ovs-vsctl list Interface bind-if` is the cleanest OVSDB view. It shows `external_ids`, `ofport`, interface type, and runtime status.
2. `ovs-ofctl show br-int` maps OpenFlow port numbers to OVS interface names. Find the `ofport` for `bind-if`.
3. `ovs-ofctl dump-flows ... grep "in_port=..."` searches local OpenFlow for rules mentioning that OVS port number. Do not expect every logical rule to literally contain `bind-port`.
4. `ovn-sbctl --ovs lflow-list bind-ls` asks OVN to show Southbound logical flows and, when possible, related local OpenFlow rows. This is the bridge between logical flows and local OVS flows.

> Mental model: `bind-port` is the human/logical join key. `bind-if` is the local OVS device name. `ofport` is the local OpenFlow number. `Port_Binding.chassis` is the SB proof that OVN connected the logical port to a real chassis.

## Optional: Break the Binding on Purpose

Delete only the local OVS interface. The NB logical port stays, the SB `Port_Binding` stays, but the binding should eventually lose its chassis.

```sh
ovs-vsctl --if-exists del-port br-int bind-if
ovn-sbctl --columns=logical_port,type,mac,chassis,datapath list Port_Binding bind-port
ovn-nbctl list Logical_Switch_Port bind-port
```

1. `ovs-vsctl --if-exists del-port br-int bind-if` removes the local OVS claim.
2. `ovn-sbctl ... Port_Binding bind-port` shows whether the runtime binding has become unbound again.
3. `ovn-nbctl list Logical_Switch_Port bind-port` proves the NB intent still exists even after local OVS stopped claiming it.

## Cleanup

Remove everything this lesson created.

```sh
ovs-vsctl --if-exists del-port br-int bind-if
ovn-nbctl --if-exists ls-del bind-ls
```

1. `ovs-vsctl --if-exists del-port br-int bind-if` removes the local OVS interface if it still exists.
2. `ovn-nbctl --if-exists ls-del bind-ls` removes the logical switch and its logical port from NB. `ovn-northd` will remove the corresponding SB rows.

## Retrieval Check

Answer from memory before looking back.

Which Southbound table proves whether a logical port has been bound to a chassis?

- Logical_Flow
- Port_Binding
- Chassis_Private

<details>
<summary>Answer</summary>

**Port_Binding**

</details>

Which OVS Interface external ID claims a logical port name?

- iface-id
- system-id
- bridge-id

<details>
<summary>Answer</summary>

**iface-id**

</details>

What local number does OpenFlow use for the OVS interface?

- datapath
- ofport
- UUID

<details>
<summary>Answer</summary>

**ofport**

</details>

If NB has an LSP but SB chassis is empty, what do you have?

- Kernel proof
- Northbound intent
- Provider VLAN

<details>
<summary>Answer</summary>

**Northbound intent**

</details>

## Primary Sources

- [`ovn-nb.5`](../../ovn/ovn-nb.5): `Logical_Switch` and `Logical_Switch_Port`.
- [`ovn-sb.5`](../../ovn/ovn-sb.5): `Port_Binding`, `Chassis`, `Encap`, and logical flows.
- [`ovn-controller.8.xml`](../../ovn/controller/ovn-controller.8.xml): how the local controller connects SB DB and local OVSDB.
- [`ovs-vswitchd.conf.db.5`](../../ovn/ovs/vswitchd/ovs-vswitchd.conf.db.5): OVS `Bridge`, `Port`, and `Interface` schema.

> Ask your agent-teacher to decode any field in `Port_Binding` or `Interface` that is still unclear.

[Lesson 12: Who Binds A Port? →](0012-who-binds-a-port.md) · [Course home](../README.md)
