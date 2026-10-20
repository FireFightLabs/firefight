---
name: upstash_box
when: Finding why an Upstash Box failed, stopped answering, ran out of memory or disk, or what an agent or command printed inside it
tools: [search_logs, query_metrics, box_account, box_logs, box_metrics]
---
Each active Box is on the resource map by its name, or its id when it has none, with its state, size and runtime.

1. Call `search_logs` for the box over the trouble for what it printed, newest first, each line with its level and whether the system, the agent or a command printed it. Narrow with `text`.
2. Call `query_metrics` for the box for its CPU, memory and disk over time. Memory or disk at the box's size is a box that needs a larger size or less work, and CPU pinned while nothing prints is a command stuck in a loop.
3. Call `box_account` for each active box with what it costs, when the question is which box spends or whether one is still running.
4. For more than the capabilities show, call `box_logs` or `box_metrics` for the box with Upstash's own arguments.
5. Say which box, since when and what it printed or ran out of. Pausing, resizing or deleting a box is for a person to decide.
