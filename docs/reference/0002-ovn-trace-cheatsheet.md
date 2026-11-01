# `ovn-trace` Cheatsheet

_Use this when you want to ask: “What would OVN do with this packet?”_

## Shape

```sh
ovn-trace --minimal <logical-datapath> '<packet-match>'
```

`<logical-datapath>` is usually a logical switch or logical router name. In the tutorial topology, start with `sw0` or `sw1`.

## Ingress Port

Tell OVN where the hypothetical packet enters.

`inport == "sw0-port1"`

## Ethernet

Set source and destination MACs so port security and routing can match.

`eth.src == 50:54:00:00:00:01`

`eth.dst == 00:00:00:00:ff:01`

## IP

Set source, destination, and TTL for routed IP behavior.

`ip4.src == 192.168.0.2`

`ip4.dst == 11.0.0.2`

`ip.ttl == 64`

## Read Minimal Output

For the tutorial packet, the important actions are:

```text
ip.ttl--;
eth.src = 00:00:00:00:ff:02;
eth.dst = 50:54:00:00:00:03;
output("sw1-port1");
```

Interpretation: the logical router decremented TTL, rewrote Ethernet addresses for the next hop, and delivered the packet to `sw1-port1`.

## Primary Sources

Use the local [OVN sandbox tutorial](../../ovn/Documentation/tutorials/ovn-sandbox.rst), especially “Using ovn-trace.” For the deeper manual, see [local `ovn-trace.8.xml`](../../ovn/utilities/ovn-trace.8.xml).
