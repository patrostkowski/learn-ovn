# Follow a Port Binding

_Your next OVN skill: connect a logical port name to the local OVS interface that realizes it._

## The Model

A logical switch port is OVN's name for an attachment point. A local OVS interface realizes that attachment point when its `external_ids:iface-id` equals the logical port name.

```text
NB Logical_Switch_Port: sw0-port1
  -> SB Port_Binding: logical_port=sw0-port1
  -> local OVS Interface p1: external_ids:iface-id=sw0-port1
  -> ovn-controller binds the Port_Binding to this chassis
```

The join key is the name `sw0-port1`. Follow that string across the three surfaces.

## Sandbox Exercise

Run these in the sandbox shell after `./ovn-setup.sh`.

Start in the Northbound DB:

```sh
ovn-nbctl lsp-list sw0
ovn-nbctl lsp-get-addresses sw0-port1
```

Move to the Southbound binding row:

```sh
ovn-sbctl list port_binding sw0-port1
```

Now find the local OVS interface that claims the same logical port:

```sh
ovs-vsctl get Interface p1 external_ids:iface-id
ovs-vsctl list Interface p1
```

Compare with the second sandbox port:

```sh
ovs-vsctl get Interface p2 external_ids:iface-id
ovn-sbctl list port_binding sw1-port1
```

## What To Notice

### Logical name

`sw0-port1` is not a Linux device name. It is OVN's logical port name.

### Local device

`p1` is the sandbox's OVS interface name. It claims `sw0-port1` through `iface-id`.

### Binding row

`Port_Binding` is the Southbound row where OVN records how the logical port is realized.

## Retrieval Check

Answer from memory before peeking back at the model.

**1.** What is the join key between the logical port and local interface?

- sw0-port1
- br-int
- lrp0

<details>
<summary>Answer</summary>

**sw0-port1**

</details>

**2.** Which OVS external ID names the logical port?

- iface-id
- system-id
- ofport-id

<details>
<summary>Answer</summary>

**iface-id**

</details>

**3.** Which Southbound table represents the binding?

- Port_Group
- Port_Binding
- Logical_Flow

<details>
<summary>Answer</summary>

**Port_Binding**

</details>

## What To Read

Primary source: [`ovn-sb.5` Port_Binding table](../../ovn/ovn-sb.5). Keep the [port binding map](../reference/0006-port-binding-map.md) nearby while comparing `sw0-port1` and `sw1-port1`.

If any row has too much detail, ask the agent to decode only the fields `logical_port`, `chassis`, `mac`, and `type`.
