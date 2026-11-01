# Kube-OVN CRDs to OVN

_Learn how Kube-OVN turns Kubernetes CRDs such as VPC, Subnet, ACL, EIP, SNAT, DNAT, and SecurityGroup into concrete OVN objects you can create by hand in the sandbox._

## The Model

Kube-OVN is a Kubernetes controller layer over OVN. A user creates a Kubernetes object. Kube-OVN reconciles it. The controller writes OVN Northbound rows. Then the same OVN path you already learned takes over: `ovn-northd` compiles NB state to SB logical flows, and `ovn-controller` programs local OVS.

Kube-OVN CRD -> controller reconcile -> OVN NB object -> SB logical flows -> OVS OpenFlow

This lesson is deliberately not about running Kubernetes. It uses the OVN sandbox to reproduce the OVN objects that Kube-OVN would have created.

## Translation Map

Use this table as your high-level decoder when reading Kube-OVN objects.

| Kube-OVN abstraction | Main source path | OVN underneath | Sandbox command family |
|---|---|---|---|
| `Vpc` | [`pkg/controller/vpc.go`](../../../kubeovn/kube-ovn/pkg/controller/vpc.go) | Logical router, static routes, router policies, peer router ports, router load balancers | `lr-add`, `lr-route-add`, `lr-policy-add`, `lr-lb-add` |
| `Subnet` | [`pkg/controller/subnet.go`](../../../kubeovn/kube-ovn/pkg/controller/subnet.go) | Logical switch, optional router patch port, DHCP options, ACLs, load balancer attachment | `ls-add`, `lrp-add`, `lsp-add`, `acl-add` |
| `Subnet.spec.acls` | [`pkg/ovs/ovn-nb-acl.go`](../../../kubeovn/kube-ovn/pkg/ovs/ovn-nb-acl.go) | Logical switch ACL rows | `acl-add`, `acl-list` |
| `OvnSnatRule` | [`pkg/controller/ovn_snat.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_snat.go) | Logical router NAT row with type `snat` | `lr-nat-add ... snat` |
| `OvnFip` | [`pkg/controller/ovn_fip.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_fip.go) | Logical router NAT row with type `dnat_and_snat` | `lr-nat-add ... dnat_and_snat` |
| `OvnDnatRule` | [`pkg/controller/ovn_dnat.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_dnat.go) | Load balancer VIP/backend attached to the logical router | `lb-add`, `lr-lb-add` |
| `SecurityGroup` | [`pkg/apis/.../security-group.go`](../../../kubeovn/kube-ovn/pkg/apis/kubeovn/v1/security-group.go) | Port group plus ACLs | `pg-add`, `pg-add-port`, `acl-add` |
| `VpcNatGateway` | [`pkg/controller/vpc_nat_gateway.go`](../../../kubeovn/kube-ovn/pkg/controller/vpc_nat_gateway.go) | Kubernetes workload plus routes and in-pod iptables/nftables behavior | Partly `lr-route-add`; not fully sandbox-only |
| `ProviderNetwork` / `Vlan` | [`provider-network.go`](../../../kubeovn/kube-ovn/pkg/apis/kubeovn/v1/provider-network.go), [`vlan.go`](../../../kubeovn/kube-ovn/pkg/apis/kubeovn/v1/vlan.go) | Host OVS/provider NIC integration for underlay networks | Not faithfully reproduced in dummy sandbox |
| `Vip` | [`pkg/controller/vip.go`](../../../kubeovn/kube-ovn/pkg/controller/vip.go) | Logical switch port or virtual logical switch port for a reserved/floating virtual IP | `lsp-add`, `lsp-set-addresses`, virtual-port options |
| `QoSPolicy` | [`pkg/controller/qos_policy.go`](../../../kubeovn/kube-ovn/pkg/controller/qos_policy.go) | Binding metadata plus OVS/OVN QoS behavior on EIP or NAT gateway traffic | Mostly outside this minimal OVN-only lab |

## Before You Start

Run this lesson in the sandbox shell. If your sandbox is fresh, recreate the tutorial topology first:

```sh
./ovn-setup.sh
```

1. `./ovn-setup.sh` creates the original OVN tutorial topology: logical switches, router, logical switch ports, local OVS ports, and bindings. The Kube-OVN lab builds separate `ko-` objects beside that topology.

The commands below create separate objects prefixed with `ko-`, so they do not overwrite the earlier tutorial topology.

## Lab 1: VPC + Subnet

Kube-OVN's `Vpc` behaves like an OVN logical router. A routed overlay `Subnet` behaves like a logical switch connected to that router by a router-port/switch-port pair.

```sh
ovn-nbctl --may-exist lr-add ko-vpc
ovn-nbctl --may-exist ls-add ko-subnet-a
ovn-nbctl --may-exist lrp-add ko-vpc ko-vpc-ko-subnet-a 00:00:00:00:aa:01 10.10.0.1/24
ovn-nbctl --may-exist lsp-add ko-subnet-a ko-subnet-a-ko-vpc
ovn-nbctl lsp-set-type ko-subnet-a-ko-vpc router
ovn-nbctl lsp-set-addresses ko-subnet-a-ko-vpc 00:00:00:00:aa:01
ovn-nbctl lsp-set-options ko-subnet-a-ko-vpc router-port=ko-vpc-ko-subnet-a
```

1. `ovn-nbctl --may-exist lr-add ko-vpc` creates an OVN logical router named `ko-vpc`. This is the manual equivalent of the core OVN object behind a Kube-OVN `Vpc`.
2. `ovn-nbctl --may-exist ls-add ko-subnet-a` creates an OVN logical switch named `ko-subnet-a`. This is the manual equivalent of the switching domain behind a Kube-OVN `Subnet`.
3. `ovn-nbctl --may-exist lrp-add ko-vpc ko-vpc-ko-subnet-a 00:00:00:00:aa:01 10.10.0.1/24` creates the router-side interface. It gives `ko-vpc` a port named `ko-vpc-ko-subnet-a` with MAC `00:00:00:00:aa:01` and gateway IP `10.10.0.1/24`.
4. `ovn-nbctl --may-exist lsp-add ko-subnet-a ko-subnet-a-ko-vpc` creates the switch-side port that will connect `ko-subnet-a` to the router port.
5. `ovn-nbctl lsp-set-type ko-subnet-a-ko-vpc router` marks that switch port as a router attachment, not a normal workload/pod port.
6. `ovn-nbctl lsp-set-addresses ko-subnet-a-ko-vpc 00:00:00:00:aa:01` tells the switch-side router port what MAC address to advertise for the router attachment.
7. `ovn-nbctl lsp-set-options ko-subnet-a-ko-vpc router-port=ko-vpc-ko-subnet-a` links the switch-side logical switch port to the router-side logical router port. This is the key that joins both halves.

Observe the Northbound result:

```sh
ovn-nbctl show ko-vpc
ovn-nbctl show ko-subnet-a
```

1. `ovn-nbctl show ko-vpc` prints the logical router and should show the router port you created.
2. `ovn-nbctl show ko-subnet-a` prints the logical switch and should show the router-type logical switch port connected to `ko-vpc`.

Implementation anchor: Kube-OVN calls `CreateLogicalSwitch` from `handleAddOrUpdateSubnet`, which creates or updates the switch and router patch ports when the subnet needs a router.

## Lab 2: Pod Port

A pod or allocated IP eventually needs a logical switch port. The important join key is still the logical port name.

```sh
ovn-nbctl --may-exist lsp-add ko-subnet-a pod-a
ovn-nbctl lsp-set-addresses pod-a "50:54:00:00:10:01 10.10.0.10"
```

1. `ovn-nbctl --may-exist lsp-add ko-subnet-a pod-a` creates a normal logical switch port named `pod-a` on `ko-subnet-a`. In a real cluster, this is the OVN-side object that represents a pod NIC.
2. `ovn-nbctl lsp-set-addresses pod-a "50:54:00:00:10:01 10.10.0.10"` assigns the port a fixed MAC and IP. OVN uses this for logical L2/L3 delivery, ARP behavior, and port security-style checks.

Inspect it:

```sh
ovn-nbctl lsp-list ko-subnet-a
ovn-nbctl lsp-get-addresses pod-a
```

1. `ovn-nbctl lsp-list ko-subnet-a` lists all logical switch ports attached to the subnet switch, including the router attachment and `pod-a`.
2. `ovn-nbctl lsp-get-addresses pod-a` verifies the exact MAC/IP tuple stored on the logical switch port.

> In a real Kube-OVN cluster, IPAM, pod annotations, interface binding, and `external_ids:iface-id` connect this logical port to a pod interface. Here we only create the OVN side.

## Lab 3: Subnet ACL

`Subnet.spec.acls` becomes OVN ACL rows attached to the logical switch. This example drops traffic from `pod-a` to the tutorial destination `11.0.0.2`.

```sh
ovn-nbctl --wait=sb --may-exist acl-add ko-subnet-a from-lport 1001 'inport == "pod-a" && ip4.dst == 11.0.0.2' drop
ovn-nbctl acl-list ko-subnet-a
ovn-sbctl lflow-list ko-subnet-a
```

1. `ovn-nbctl --wait=sb --may-exist acl-add ko-subnet-a from-lport 1001 'inport == "pod-a" && ip4.dst == 11.0.0.2' drop` creates a logical switch ACL on `ko-subnet-a`. `from-lport` means traffic leaving a logical port, priority `1001` decides precedence, the match selects traffic from `pod-a` to `11.0.0.2`, and `drop` is the action. `--wait=sb` waits until `ovn-northd` has propagated the change into the Southbound DB.
2. `ovn-nbctl acl-list ko-subnet-a` reads the Northbound ACL attached to the logical switch. This is the intent-level object Kube-OVN would create from `Subnet.spec.acls`.
3. `ovn-sbctl lflow-list ko-subnet-a` reads the compiled logical flows generated from that ACL. This confirms the NB intent moved into the SB pipeline.

Implementation anchor: `UpdateLogicalSwitchACL` recreates Kube-OVN-managed ACLs for a subnet and stores them as OVN ACLs associated with the logical switch.

## Lab 4: SNAT

`OvnSnatRule` becomes an OVN router NAT row with type `snat`. In Kube-OVN source, `handleAddOvnSnatRule` calls `OVNNbClient.AddNat(vpcName, NATTypeSNAT, externalIP, logicalCIDR, ...)`.

```sh
ovn-nbctl --may-exist lr-nat-add ko-vpc snat 172.20.0.100 10.10.0.0/24
ovn-nbctl lr-nat-list ko-vpc
```

1. `ovn-nbctl --may-exist lr-nat-add ko-vpc snat 172.20.0.100 10.10.0.0/24` creates a NAT row on router `ko-vpc`. Type `snat` means packets sourced from logical CIDR `10.10.0.0/24` can leave as external IP `172.20.0.100`.
2. `ovn-nbctl lr-nat-list ko-vpc` prints NAT rows attached to the logical router so you can confirm the SNAT rule exists.

Read it as: traffic whose logical source is `10.10.0.0/24` can be translated to external IP `172.20.0.100`.

## Lab 5: Floating IP

`OvnFip` is different from plain SNAT. Kube-OVN uses OVN NAT type `dnat_and_snat`, so one external IP maps both inbound and outbound traffic for one internal IP.

```sh
ovn-nbctl --may-exist lr-nat-add ko-vpc dnat_and_snat 172.20.0.101 10.10.0.10 pod-a 50:54:00:00:10:01
ovn-nbctl lr-nat-list ko-vpc
```

1. `ovn-nbctl --may-exist lr-nat-add ko-vpc dnat_and_snat 172.20.0.101 10.10.0.10 pod-a 50:54:00:00:10:01` creates a floating-IP style NAT row on `ko-vpc`. External IP `172.20.0.101` maps to internal IP `10.10.0.10`. The optional `pod-a` and MAC bind distributed NAT behavior to the logical switch port that owns the internal IP.
2. `ovn-nbctl lr-nat-list ko-vpc` verifies that the `dnat_and_snat` row is now attached to the router.

Implementation anchor: `handleAddOvnFip` calls `AddNat` with `NATTypeDNATAndSNAT`. For distributed FIP, Kube-OVN can also pass the logical port and MAC, which pins the NAT behavior to where that logical port lives.

## Lab 6: DNAT

This one is easy to guess wrong. Kube-OVN's `OvnDnatRule` is implemented as an OVN load balancer VIP/backend attached to the VPC router, not as a simple router `dnat` row.

```sh
ovn-nbctl --may-exist lb-add ko-dnat 172.20.0.102:8080 10.10.0.10:80 tcp
ovn-nbctl --may-exist lr-lb-add ko-vpc ko-dnat
ovn-nbctl list load_balancer ko-dnat
```

1. `ovn-nbctl --may-exist lb-add ko-dnat 172.20.0.102:8080 10.10.0.10:80 tcp` creates an OVN load balancer named `ko-dnat`. Its VIP is `172.20.0.102:8080`, its backend is `10.10.0.10:80`, and the protocol is TCP.
2. `ovn-nbctl --may-exist lr-lb-add ko-vpc ko-dnat` attaches that load balancer to the logical router `ko-vpc`. Without this attachment, the router pipeline would not use the load balancer.
3. `ovn-nbctl list load_balancer ko-dnat` prints the NB Load_Balancer row so you can see the VIP-to-backend mapping that Kube-OVN's `OvnDnatRule` would have produced.

Implementation anchor: `AddDnatRule` creates the load balancer, adds VIP `externalIP:externalPort -> internalIP:internalPort`, then attaches the load balancer to the logical router with `LogicalRouterUpdateLoadBalancers`.

## Lab 7: Security Group

A Kube-OVN `SecurityGroup` is naturally modeled as an OVN port group plus ACLs. The port group gives ACLs a stable target: all member ports.

```sh
ovn-nbctl pg-add ko-sg-web
ovn-nbctl pg-add-port ko-sg-web pod-a
ovn-nbctl --may-exist acl-add ko-sg-web to-lport 1001 'outport == @ko-sg-web && ip4 && tcp && tcp.dst == 80' allow-related
ovn-nbctl acl-list ko-sg-web
```

1. `ovn-nbctl --may-exist pg-add ko-sg-web` creates an OVN port group named `ko-sg-web`. A port group is a named set of logical switch ports.
2. `ovn-nbctl pg-add-port ko-sg-web pod-a` adds logical switch port `pod-a` to that group. ACLs can now match the group instead of naming individual ports.
3. `ovn-nbctl --may-exist acl-add ko-sg-web to-lport 1001 'outport == @ko-sg-web && ip4 && tcp && tcp.dst == 80' allow-related` attaches an ACL to the port group. `to-lport` means traffic entering the destination logical port, `@ko-sg-web` means any port in the group, and `allow-related` allows matching traffic plus related connection-tracking traffic.
4. `ovn-nbctl acl-list ko-sg-web` prints ACLs attached to the port group so you can verify the security-group-like rule exists.

Read the ACL match aloud: if the packet is going to any logical port in `@ko-sg-web`, is IPv4 TCP, and targets port 80, allow it and related traffic.

## What The Sandbox Cannot Fully Show

### `VpcNatGateway`

It is a Kubernetes workload plus routes and iptables/nftables behavior inside a gateway pod. OVN can show route injection, but not the full pod-side NAT behavior.

### `ProviderNetwork` / `Vlan`

These depend on real host interfaces, provider bridges, VLAN subinterfaces, and node readiness. The dummy sandbox has no physical underlay.

### IPAM and status

Kube-OVN also allocates IPs, patches CRD status, manages finalizers, and validates conflicts. Those are Kubernetes controller behaviors, not OVN NB objects.

## Cleanup

Remove the lesson-created objects when you are done:

```sh
ovn-nbctl --if-exists lr-lb-del ko-vpc ko-dnat
ovn-nbctl --if-exists lb-del ko-dnat
ovn-nbctl --if-exists pg-del ko-sg-web
ovn-nbctl --if-exists lr-del ko-vpc
ovn-nbctl --if-exists ls-del ko-subnet-a
```

1. `ovn-nbctl --if-exists lr-lb-del ko-vpc ko-dnat` detaches the DNAT-style load balancer from the logical router if the attachment exists.
2. `ovn-nbctl --if-exists lb-del ko-dnat` deletes the load balancer row created for the DNAT lab.
3. `ovn-nbctl --if-exists pg-del ko-sg-web` deletes the security-group-like port group and its attached ACLs.
4. `ovn-nbctl --if-exists lr-del ko-vpc` deletes the lesson logical router. This also removes router-owned state such as NAT rows on that router.
5. `ovn-nbctl --if-exists ls-del ko-subnet-a` deletes the lesson logical switch and its logical switch ports.

## Retrieval Check

Answer from memory before peeking back at the table.

**1.** What is the core OVN object underneath a Kube-OVN `Vpc`?

- Logical switch
- Logical router
- Port binding

<details>
<summary>Answer</summary>

**Logical router**

</details>

**2.** What OVN object does Kube-OVN use for `OvnDnatRule`?

- Load balancer
- Router dnat
- Static route

<details>
<summary>Answer</summary>

**Load balancer**

</details>

**3.** Which OVN NAT type backs a floating IP?

- snat
- lb-vip
- dnat_and_snat

<details>
<summary>Answer</summary>

**dnat_and_snat**

</details>

**4.** What OVN object gives SecurityGroup ACLs a reusable set of member ports?

- Route table
- Port group
- DHCP option

<details>
<summary>Answer</summary>

**Port group**

</details>

## Primary Sources

Read the Kube-OVN implementation next to this lesson: [`subnet.go`](../../../kubeovn/kube-ovn/pkg/controller/subnet.go), [`vpc.go`](../../../kubeovn/kube-ovn/pkg/controller/vpc.go), [`ovn_snat.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_snat.go), [`ovn_dnat.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_dnat.go), and [`ovn_fip.go`](../../../kubeovn/kube-ovn/pkg/controller/ovn_fip.go).

For command syntax, keep [`ovn-nbctl.8.xml`](../../ovn/utilities/ovn-nbctl.8.xml) open. If any output is unclear, ask me to interpret it with you.
