# Who Binds A Port?

_The Southbound DB does not tell OVS how to attach a port. The local `ovn-controller` discovers a local interface and writes the binding *back* into SB. This lesson fixes the direction of that arrow._

## The Misconception To Kill

“A port is created in SB with `iface-id=...` and then the controller programs itself.”

**No.** `iface-id` is **not** a Southbound field. It never appears in the OVN SB schema. It lives only in the **local OVSDB** on each node, as `Interface.external_ids:iface-id`. The Southbound side of the join is a different field: `Port_Binding.logical_port`.

The controller does not read an instruction from SB telling it what to do. It watches its *own* local OVS for interfaces that carry an `iface-id`, then looks up the matching SB `Port_Binding` by **name** and stamps itself into it.

## The Two-Plane Contract

The only shared agreement between the local node and the distributed DB is a **string**:

```text
OVS Interface.external_ids:iface-id   ==   SB Port_Binding.logical_port
```

- **SB writes: nothing**: `Port_Binding{logical_port=who-port, chassis=[]}` is a *slot*. `ovn-northd` created it; it is empty until claimed.
- **Local OVS speaks**: An interface appears with `external_ids:iface-id=who-port`. This is set on the node, by the node.
- **Controller answers**: `ovn-controller` matches by name, writes `chassis=<itself>`, programs OpenFlow on `br-int`.

> Direction: OVS → controller → SB. Not SB → OVS.

## Who Writes What

| Field | Lives in | Written by | Meaning |
|---|---|---|---|
| `Logical_Switch_Port.name` | NB DB | You / CMS (`ovn-nbctl`) | The logical port name (the join key). |
| `Port_Binding.logical_port` | SB DB | `ovn-northd` | Compiled copy of the name; the slot to fill. |
| `Port_Binding.chassis` | SB DB | `ovn-controller` | Which node claimed the port. Empty = unbound. |
| `Interface.external_ids:iface-id` | Local OVSDB | The node (CMS / agent / CNI) | The local claim: “I realize logical port *X*.” |
| OpenFlow on `br-int` | Local OVS | `ovn-controller` | The datapath for that logical port’s `ofport`. |

## Lab: Watch The Arrow Point The Right Way

**Step 1 - create NB intent, then look at SB. No `iface-id` anywhere.**

```sh
ovn-nbctl --wait=sb --may-exist ls-add who-ls
ovn-nbctl --wait=sb --may-exist lsp-add who-ls who-port
ovn-nbctl --wait=sb lsp-set-addresses who-port "50:54:00:00:40:10 10.40.0.10"
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding who-port
ovn-sbctl list Port_Binding who-port | grep -i iface || echo "no iface-id in SB (expected)"
```

1. The `ls-add`/`lsp-add` commands write intent into NB; `--wait=sb` blocks until `ovn-northd` has compiled it.
2. The `Port_Binding` exists with `chassis=[]` - the slot, still empty.
3. The final `grep` proves the point: `iface-id` is not a Southbound concept. SB has `logical_port`.

**Step 2 - the local node speaks. Add an OVS interface with the matching `iface-id`.**

```sh
ovs-vsctl --may-exist add-port br-int who-if -- set Interface who-if external_ids:iface-id=who-port
ovs-vsctl get Interface who-if external_ids
```

1. `add-port br-int who-if` creates a local OVS port on the integration bridge.
2. `external_ids:iface-id=who-port` is the claim: this local device realizes logical port `who-port`. Nothing in SB prompted this - you did it on the node.

**Step 3 - the controller answers. Watch SB fill itself in.**

```sh
ovn-sbctl --columns=logical_port,chassis,up list Port_Binding who-port
ovn-sbctl show
ovs-vsctl get Interface who-if external_ids
```

1. `Port_Binding.chassis` should now be non-empty: `ovn-controller` wrote this node’s chassis UUID.
2. `up: true` means the local interface is up.
3. `Interface.external_ids` now also contains `ovn-installed="true"` - the controller’s acknowledgement that OpenFlow is programmed.

> That is the whole mechanism: **nobody told OVS to bind. OVS declared a local interface; the controller did the binding.**

## The Manual Override (And Why It Is Rare)

`ovn-sbctl` can force a binding for ports that have *no* local interface. This is a debug/edge tool, not the normal path.

```sh
ovn-sbctl lsp-unbind who-port
ovn-sbctl --columns=logical_port,chassis list Port_Binding who-port
ovn-sbctl lsp-bind who-port chassis-1
ovn-sbctl --columns=logical_port,chassis list Port_Binding who-port
```

1. `lsp-unbind who-port` resets the binding to empty.
2. `lsp-bind who-port chassis-1` forces the port onto chassis `chassis-1` by hand.
3. Because a real OVS interface still carries `iface-id=who-port`, `ovn-controller` will reclaim the binding shortly. Manual bind only “sticks” when no local interface competes for it.

> One legitimate CMS hint does exist: `Port_Binding.requested-chassis` (and `additional_chassis`). The CMS can *request* placement - used for SR-IOV, direct/baremetal ports, and live migration - but the controller still performs the bind. Absent that hint, placement is entirely the controller’s decision.

## How OpenStack Does Exactly This

OpenStack has the same separation of duties; only the names of the actors differ.

- **1. API / Neutron DB**: `openstack port create` makes a Neutron port with UUID `P`. No OVN object yet.
- **2. NB (intent)**: The ML2/OVN driver writes a `Logical_Switch_Port` named `P` (Neutron uses the port UUID as the logical port name).
- **3. SB (compiled)**: `ovn-northd` creates `Port_Binding{logical_port=P, chassis=[]}`. Still a slot.

- **4. Compute plugs the vif**: Nova, on the target compute, creates the tap/veth and sets `external_ids:iface-id=P` on the OVS interface. *This is the local claim.*
- **5. Controller binds**: `ovn-controller` on that compute matches `iface-id=P` to `logical_port=P`, writes `chassis=<compute>`, programs OpenFlow.
- **Result**: Port is “bound” and traffic flows. SB now records which compute owns the port.

**So the answer to “does SB tell the controller to create a binding?” is no.** SB provides the logical port (a slot). The trigger to bind is a *local interface appearing*, created by the compute-side agent (Nova + os-vif, or a CNI). The controller then writes the binding back into SB.

| Role | OVN generic | OpenStack | Kubernetes (Kube-OVN/OVN-K) |
|---|---|---|---|
| Creates logical port (NB) | CMS via `ovn-nbctl` | Neutron ML2/OVN | the CNI / controller |
| Compiles slot (SB) | `ovn-northd` | `ovn-northd` | `ovn-northd` |
| Sets `iface-id` locally | the node operator / CNI | Nova on the compute | the CNI plugin |
| Writes `chassis` | `ovn-controller` | `ovn-controller` | `ovn-controller` |

> In your `kubesdn` project this is exactly why the CNI sets `external_ids:iface-id=<ns>-<pod>` on the host veth and the controller-owned `ovn-controller` does the binding - the CNI never “asks” SB to bind anything.

## Cleanup

```sh
ovs-vsctl --if-exists del-port br-int who-if
ovn-nbctl --if-exists ls-del who-ls
```

1. Removing the local OVS port releases the claim; the binding will fall back to unbound.
2. Deleting the logical switch removes the NB intent, and `ovn-northd` removes the SB rows.

## Retrieval Check

Answer from memory before looking back.

Where does `iface-id` actually live?

- Southbound Port_Binding
- Local OVS database
- Northbound logical port

<details>
<summary>Answer</summary>

**Local OVS database**

</details>

Who writes the `chassis` field into `Port_Binding`?

- ovn-northd compiles rows
- ovn-nbctl writes it
- ovn-controller binds it

<details>
<summary>Answer</summary>

**ovn-controller binds it**

</details>

In OpenStack, what sets `iface-id` on the local tap?

- Neutron writes the row
- Nova plugs the vif
- northd sets the field

<details>
<summary>Answer</summary>

**Nova plugs the vif**

</details>

Which SB field lets the CMS *hint* a target chassis?

- requested-chassis column
- logical_port column
- install_lb option

<details>
<summary>Answer</summary>

**requested-chassis column**

</details>

## Primary Sources

- [`ovn-controller.8.xml`](../../ovn/controller/ovn-controller.8.xml): the local controller writes `Chassis`, `Encap`, and `Port_Binding`.
- [`ovn-sb.5`](../../ovn/ovn-sb.5): `Port_Binding` columns, including `logical_port`, `chassis`, and `requested-chassis`.
- [`ovs-vswitchd.conf.db.5`](../../ovn/ovs/vswitchd/ovs-vswitchd.conf.db.5): the OVS `Interface.external_ids` map where `iface-id` lives.
- [VIF plug providers](../../ovn/Documentation/topics/vif-plug-providers/vif-plug-providers.rst): how the compute side sets `iface-id`.

> Ask your agent-teacher to trace any specific port across NB, SB, and OVS in your own sandbox.

[← Lesson 11](0011-nb-sb-ovs-port-binding.md) · [Lesson 13: Port Binding Lab →](0013-port-binding-lab.md) · [Port Binding Map](../reference/0006-port-binding-map.md) · [Bridge / Port / Interface](../reference/0009-ovs-bridge-port-interface.md) · [OVN Table Map](../reference/0008-ovn-table-map.md) · [Course home](../README.md)
