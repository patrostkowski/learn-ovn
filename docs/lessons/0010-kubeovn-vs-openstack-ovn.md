# Kube-OVN vs OpenStack OVN

_Compare two real OVN integrations: Kube-OVN as a Kubernetes-native controller system, and OpenStack Neutron ML2/OVN as an OpenStack networking backend._

## The Shared Core

Both systems are control planes above the same OVN databases. They differ in the APIs they expose and the reconciliation code they run, but once they write Northbound rows, the lower OVN path is shared.

User-facing API -> integration controller -> OVN Northbound -> ovn-northd -> OVN Southbound -> ovn-controller -> OVS

The learning trick is to separate *product abstraction* from *OVN primitive*. Kube-OVN and OpenStack often create the same OVN row types, but for different reasons and with different ownership rules.

## One Sentence Difference

Kube-OVN

Kube-OVN extends Kubernetes with network CRDs, then reconciles those CRDs into OVN objects for pods, subnets, VPCs, egress, NAT gateways, security groups, and provider networks.

OpenStack ML2/OVN

OpenStack Neutron exposes cloud networking resources, then its OVN mechanism driver converts Neutron networks, ports, routers, DHCP, security groups, floating IPs, and gateways into OVN objects.

## Architecture Comparison

| Question | Kube-OVN | OpenStack ML2/OVN |
|---|---|---|
| Primary API | Kubernetes API plus Kube-OVN CRDs such as `Vpc`, `Subnet`, `OvnFip`, `OvnSnatRule`, `SecurityGroup`. | OpenStack Neutron API resources such as network, subnet, port, router, security group, floating IP. |
| Main reconciler | Kubernetes controllers under [`pkg/controller/`](../../../kubeovn/kube-ovn/pkg/controller/) observe cluster objects and call OVN helpers under [`pkg/ovs/`](../../../kubeovn/kube-ovn/pkg/ovs/). | Neutron ML2/OVN code under [`ovn_client.py`](../../../openstack/neutron/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/ovn_client.py) and OVSDB command classes under [`commands.py`](../../../openstack/neutron/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/commands.py). |
| Workload identity | Pod or Kubernetes workload identity, usually tied to Kubernetes namespace/name, pod annotations, node state, and Kube-OVN IPAM. | Neutron port UUID, later matched by Nova through local OVS `external_ids:iface-id`. |
| Main networking unit | `Subnet` is a first-class CRD and usually maps to an OVN logical switch. | Neutron `network` maps to an OVN logical switch; Neutron `subnet` mainly contributes IPAM, routes, and DHCP options. |
| Router abstraction | `Vpc` maps naturally to an OVN logical router plus routes, policies, peerings, and load balancer attachment. | Neutron router maps to an OVN logical router; router interfaces and gateway ports are represented by Neutron ports and router ports. |
| Policy abstraction | Kube-OVN can use subnet ACLs, network policy behavior, security groups, and port groups depending on feature. | Neutron security groups are implemented as port groups plus ACLs; ingress maps to `to-lport`, egress maps to `from-lport`. |
| External connectivity | Includes CRDs and controllers for EIP, SNAT, DNAT, VPC NAT gateway, provider networks, VLANs, and host/underlay integration. | Uses router gateway ports, provider networks, gateway chassis scheduling, SNAT rows, and floating IP NAT rows. |
| Operational boundary | Must fit Kubernetes scheduling, node agents, CNI behavior, pod lifecycle, and Kubernetes API status updates. | Must fit OpenStack API/database semantics, Nova port binding, ML2 mechanism driver behavior, gateway scheduling, and Neutron service plugins. |

## Same OVN Primitive, Different Story

| OVN primitive | Kube-OVN meaning | OpenStack meaning |
|---|---|---|
| `Logical_Switch` | Usually a Kube-OVN `Subnet`. | Usually a Neutron `network`. |
| `Logical_Switch_Port` | Pod port, VM port, router attachment, VIP, or provider-related port depending on controller path. | Neutron port, router interface switch-side port, gateway switch-side port, or provider network port. |
| `Logical_Router` | Kube-OVN `Vpc`. | Neutron router. |
| `NAT snat` | `OvnSnatRule` or VPC egress behavior. | Router gateway SNAT for tenant subnets. |
| `NAT dnat_and_snat` | `OvnFip` floating IP behavior. | Neutron floating IP behavior. |
| `Load_Balancer` | Kube-OVN uses it for some DNAT-style VIP/backend behavior and service-related behavior. | Core Neutron ML2/OVN lesson excludes Octavia; OpenStack load balancing usually belongs to Octavia, not basic Neutron networking. |
| `Port_Group` | Kube-OVN `SecurityGroup` and sometimes grouped policy targets. | Neutron security group implementation target. |
| `DHCP_Options` | Subnet/pod DHCP behavior when Kube-OVN needs OVN native DHCP. | Neutron subnet DHCP options attached to eligible logical switch ports. |

## Key Difference 1: Ownership Model

Kube-OVN owns networking through Kubernetes custom resources. Its desired state lives in the Kubernetes API, and controllers continuously reconcile that state into OVN.

OpenStack owns networking through Neutron. Desired state lives in Neutron's API and database model, and the ML2/OVN mechanism driver writes the corresponding OVN rows during Neutron operations.

> Practical consequence: when debugging Kube-OVN, first ask “which Kubernetes object owns this OVN row?” When debugging OpenStack, first ask “which Neutron resource owns this OVN row?”

## Key Difference 2: Naming

Kube-OVN names often preserve Kubernetes-facing names such as VPC, subnet, pod, or generated controller names. OpenStack deliberately prefixes many OVN names with Neutron-oriented forms.

| Object | Kube-OVN style | OpenStack style |
|---|---|---|
| Logical router | Often VPC name, such as `ovn-cluster` or a custom VPC name. | `neutron-<router-uuid>` from `ovn_name()`. |
| Logical switch | Often subnet name. | `neutron-<network-uuid>`. |
| Router port | Generated from VPC/subnet relationship. | `lrp-<neutron-port-uuid>`. |
| Security group port group | Kube-OVN security-group-oriented name. | `pg-<security-group-uuid>`, with dashes changed to underscores. |

> Practical consequence: OpenStack OVN databases look UUID-heavy; Kube-OVN databases often look closer to Kubernetes object names.

## Key Difference 3: Subnet Meaning

This is the easiest conceptual trap.

Kube-OVN

`Subnet` is a major network object. It commonly creates the logical switch and can carry ACLs, gateway behavior, protocol settings, and VPC attachment.

OpenStack

`Network` is the logical switch. `Subnet` contributes CIDR, allocation pools, routes, DNS, and DHCP options. The subnet is important, but it is not usually the logical switch row itself.

## Key Difference 4: DNAT Choice

Floating IPs are similar: both systems use `dnat_and_snat` for one-to-one external-to-internal address mapping.

DNAT-style port forwarding can differ. In the Kube-OVN lesson, `OvnDnatRule` maps naturally to an OVN load balancer VIP/backend attached to a VPC router. In the core OpenStack lesson, we did not model load balancing because OpenStack load balancer behavior normally belongs to Octavia rather than basic Neutron ML2/OVN.

> Practical consequence: do not assume that a product object named “DNAT” always becomes an OVN NAT row. Check the integration code.

## Key Difference 5: Binding To The Host

Both systems eventually need local OVS interfaces to claim logical ports, but the surrounding machinery is different.

| Layer | Kube-OVN | OpenStack |
|---|---|---|
| Who creates workload interface? | Kubernetes CNI/node-side agents for pods. | Nova/libvirt integration for VM tap or vhost-user interfaces. |
| Join key | Logical port identity associated with pod/IP allocation and OVS interface metadata. | Neutron port UUID must match local OVS `external_ids:iface-id`. |
| Where to debug first? | Kubernetes pod annotations, Kube-OVN controller logs, node agent/CNI state, OVN LSP and Port_Binding. | Neutron port binding, Nova instance interface, local OVS Interface `iface-id`, OVN LSP and Port_Binding. |

## Quick Inspection Commands

If you created objects from Lessons 8 and 9, these commands show the contrast in the same sandbox. They do not create anything.

```sh
ovn-nbctl show ko-vpc
ovn-nbctl show neutron-os-router-a
ovn-nbctl show ko-subnet-a
ovn-nbctl show neutron-os-net-a
ovn-nbctl lr-nat-list ko-vpc
ovn-nbctl lr-nat-list neutron-os-router-a
ovn-nbctl list Port_Group ko-sg-web
ovn-nbctl list Port_Group pg-os-sg-web
```

1. `ovn-nbctl show ko-vpc` shows the Kube-OVN-style VPC logical router from Lesson 8.
2. `ovn-nbctl show neutron-os-router-a` shows the OpenStack-style Neutron router from Lesson 9.
3. `ovn-nbctl show ko-subnet-a` shows the Kube-OVN-style subnet logical switch.
4. `ovn-nbctl show neutron-os-net-a` shows the OpenStack-style network logical switch.
5. `ovn-nbctl lr-nat-list ko-vpc` and `ovn-nbctl lr-nat-list neutron-os-router-a` let you compare how both lessons expressed SNAT and floating IP rows.
6. `ovn-nbctl list Port_Group ko-sg-web` and `ovn-nbctl list Port_Group pg-os-sg-web` compare security-policy targets.

## Debugging Heuristic

Use the same three-step process for both systems, but change the first question.

| Step | Kube-OVN question | OpenStack question |
|---|---|---|
| 1. Owner | Which Kubernetes CRD, pod, subnet, VPC, or policy owns this? | Which Neutron network, port, router, subnet, security group, or floating IP owns this? |
| 2. OVN NB | Did the Kube-OVN controller write the expected NB row? | Did Neutron ML2/OVN write the expected NB row? |
| 3. OVN lower path | Did `ovn-northd` compile it and did `ovn-controller` bind/program the local chassis? | Same question: SB logical flows, Port_Binding, local OVS OpenFlow. |

## Retrieval Check

Answer from memory before looking back.

In OpenStack ML2/OVN, which Neutron abstraction usually maps to an OVN logical switch?

- Subnet
- Network
- Router

<details>
<summary>Answer</summary>

**Network**

</details>

In Kube-OVN, which CRD commonly maps to an OVN logical switch?

- Subnet
- Port
- Router

<details>
<summary>Answer</summary>

**Subnet**

</details>

In OpenStack, what must match the local OVS `external_ids:iface-id`?

- Router name
- Network name
- Neutron port ID

<details>
<summary>Answer</summary>

**Neutron port ID**

</details>

If a product object is called DNAT, what should you do before assuming it is an OVN NAT row?

- Check the integration
- Skip the source
- Assume NAT

<details>
<summary>Answer</summary>

**Check the integration**

</details>

## Primary Sources

Read these source paths when you want to verify the mappings rather than trust the lesson:

- [`kube-ovn/pkg/controller/`](../../../kubeovn/kube-ovn/pkg/controller/) for CRD reconciliation logic.
- [`kube-ovn/pkg/ovs/`](../../../kubeovn/kube-ovn/pkg/ovs/) for OVN wrapper calls.
- [`neutron/.../ovn_client.py`](../../../openstack/neutron/neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/ovn_client.py) for Neutron-to-OVN object creation.
- [`neutron/common/ovn/acl.py`](../../../openstack/neutron/neutron/common/ovn/acl.py) for OpenStack security-group ACL generation.
- [`ovn/ovn-nb.xml`](../../ovn/ovn-nb.xml) for the OVN Northbound schema both systems write to.

> Ask your agent-teacher to walk through any row you see in `ovn-nbctl list` and identify which system would own it.
