# Local OVS and OpenFlow Map

_Use this when you want to connect Southbound logical flows to what is installed on the sandbox switch._

## Logical Flows

Stored in the Southbound DB. These use OVN logical names such as logical datapaths, `inport`, and `outport`.

`ovn-sbctl lflow-list sw0`

## Translated View

Shows logical flows plus any corresponding OpenFlow that `ovn-controller` installed locally.

`ovn-sbctl --ovs lflow-list sw0`

## OpenFlow

Installed in Open vSwitch. These use bridge tables, registers, metadata, and OpenFlow actions.

`ovs-ofctl dump-flows br-int`

## Translation Chain

```text
Northbound intent
  -> ovn-northd
  -> Southbound logical flows
  -> ovn-controller
  -> OpenFlow on br-int
  -> ovs-vswitchd packet processing
```

## What To Look For

Do not try to understand every OpenFlow field yet. For now, only notice the change in vocabulary:

### OVN vocabulary

`inport`, `outport`, logical switch, logical router, `next;`, `output;`

### OVS vocabulary

`table`, `metadata`, `reg`, `actions`, `resubmit`, bridge port numbers

## Primary Sources

Use local [`ovn-controller.8`](../../ovn/controller/ovn-controller.8) for the local controller and local [`ovs-ofctl.8`](../../ovn/ovs/utilities/ovs-ofctl.8) for inspecting OpenFlow.
