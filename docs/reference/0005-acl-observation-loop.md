# ACL Observation Loop

_Use this when you change OVN policy and want to prove where the change landed._

## Repeatable ACL

```sh
ovn-nbctl --wait=sb --may-exist acl-add sw0 from-lport 1001 \
  'inport == "sw0-port1" && ip4.dst == 11.0.0.2' drop

ovn-nbctl --wait=sb acl-del sw0 from-lport 1001 \
  'inport == "sw0-port1" && ip4.dst == 11.0.0.2'
```

`--may-exist` makes the add safe to repeat. `--wait=sb` waits until `ovn-northd` has updated the Southbound DB.

## 1. NB Intent

`ovn-nbctl acl-list sw0`

Look for direction `from-lport`, priority `1001`, match `inport == "sw0-port1" && ip4.dst == 11.0.0.2`, and action `drop`.

## 2. SB Compile

`ovn-sbctl lflow-list sw0`

Look for ACL-related tables. For `from-lport`, the ingress ACL evaluation table sets verdict bits, then the ACL action table performs `drop;`.

## 3. Trace Result

`ovn-trace --ct new --minimal sw0 '...'`

A successful drop trace does not end with the destination `output("sw1-port1")` from Lesson 2.

## Command Shape

```text
acl-add ENTITY DIRECTION PRIORITY MATCH VERDICT
acl-del ENTITY DIRECTION PRIORITY MATCH
```

`ENTITY` is a logical switch or port group. `DIRECTION` is `from-lport` or `to-lport`. `PRIORITY` is higher-wins, within the ACL priority range.

## Primary Sources

Use local [`ovn-nbctl.8`](../../ovn/utilities/ovn-nbctl.8.xml) for command syntax and local [`ovn-logical-flows.7`](../../ovn/Documentation/ref/ovn-logical-flows.7.rst) for the ACL logical pipeline.
