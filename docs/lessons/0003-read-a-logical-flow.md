# Read A Logical Flow

_Your next OVN skill: read the Southbound rules that `ovn-trace` is walking through._

## The Model

`ovn-northd` compiles Northbound intent into Southbound logical flows. `ovn-trace` follows those flows for a hypothetical packet.

A logical flow is just a match-action rule with ordering:

```text
table=0 (...), priority=50, match=(...), action=(next;)
```

### Where?

`table` tells you the pipeline stage.

### Which one?

`priority` decides among matching flows.

### For what?

`match` describes the packet fields.

### Do what?

`action` tells OVN to continue, drop, rewrite, or output.

## Sandbox Exercise

In your running sandbox shell, list the logical flows for the first switch and router. The output is long; your task is only to classify lines.

```sh
ovn-sbctl lflow-list sw0

ovn-sbctl lflow-list lr0
```

Now pick one line from the output and rewrite it in this four-part form:

```text
table:    ____
priority: ____
match:    ____
action:   ____
```

## What To Notice

On `sw0`, many table names start with `ls_`. Read that as logical switch. On `lr0`, many table names start with `lr_`. Read that as logical router.

This is why Lesson 2's trace had router-looking actions such as `ip.ttl--` and Ethernet rewrites: the packet left a logical switch pipeline, crossed the router pipeline, then entered another logical switch pipeline.

## Retrieval Check

Answer from memory before peeking back at the model.

**1.** In a logical flow, what does `table` identify?

- Packet source
- Pipeline stage
- Chassis name

<details>
<summary>Answer</summary>

**Pipeline stage**

</details>

**2.** If several flows match in one table, which priority wins?

- First printed
- Lowest number
- Highest number

<details>
<summary>Answer</summary>

**Highest number**

</details>

**3.** Where does `ovn-sbctl lflow-list` read logical flows from?

- Southbound DB
- Northbound DB
- Linux kernel

<details>
<summary>Answer</summary>

**Southbound DB**

</details>

## What To Read

Primary source: [local `ovn-logical-flows.7.rst`](../../ovn/Documentation/ref/ovn-logical-flows.7.rst). Keep the [logical-flow reading guide](../reference/0003-logical-flow-reading-guide.md) open as the short version.

If a flow line is confusing, paste that exact line to the agent and ask: “Which packet would this match, and what would the action do?”
