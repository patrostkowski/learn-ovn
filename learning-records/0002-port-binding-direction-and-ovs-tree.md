# Port Binding Direction And The OVS Object Tree

The user worked hands-on in the sandbox and reached two clear insights.

## What was learned

1. **Direction of binding.** The user started with the misconception that a Southbound port "has `iface-id`" and that SB tells the controller what to do. They corrected it themselves: a *node-local* actor (CNI / Nova+os-vif / operator) creates the OVS interface and sets `external_ids:iface-id`; `ovn-controller` then discovers it, binds it, and writes `chassis` **into** SB. The user's own framing: "some other controller creates the OVS port with iface-id and then controller programs it and then chassis shows up in SB." Correct.

2. **The join key is a string, and `iface-id` is OVS-only.** `NB Logical_Switch_Port.name == SB Port_Binding.logical_port == OVS Interface.external_ids:iface-id`. `iface-id` does not exist in the SB schema; SB's field is `logical_port`.

3. **The OVS object tree.** The user hit `ovs-vsctl show` and wanted Bridge vs Port vs Interface defined. They can now be told the cardinality (`1 Bridge : N Ports`, `1 Port : N Interfaces`) and where each fact lives (VLAN on Port; `iface-id`/`ofport` on Interface; `fail_mode` on Bridge).

## Evidence

- User built a router with a switch on each end plus one host port per switch (`xd`/`xdp1`/`xdp2`, then `netA`/`lab`-style ports).
- User observed the two-stage binding: OVS port without `iface-id` left `chassis=[]`; adding `iface-id` filled it.
- User asked explicitly how to unbind and accepted that binding follows the local interface.

## Implications for future lessons

- The user's zone of proximal development now includes: the full NB->SB->OVS binding chain, router port splicing (`router-port` option), and reading `ovn-sbctl show` / `Port_Binding`.
- The user prefers **hands-on labs with observable before/after state** over abstract explanation. Continue pairing each concept with a small sandbox experiment and expected output.
- Natural next topics: `ovn-trace` through the lab-rtr topology (routing between the two switches), then Localnet/gateway ports, then `ovn-controller` internals (how it programs OpenFlow).

## Artifacts created alongside

- `lessons/0012-who-binds-a-port.html` (concept)
- `lessons/0013-port-binding-lab.html` (hands-on lab)
- `reference/0008-ovn-table-map.html`, `reference/0009-ovs-bridge-port-interface.html`
