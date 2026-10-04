---
name: axiom_triage
when: Any question about a service whose logs or traces go to Axiom, such as why it fails or slows down, which monitor fired, or what changed around it
tools: [checkmonitors, getmonitorhistory, listdatasets, getdatasetfields, search_logs, search_errors, search_traces, querydataset]
references: [sre/axiom.md, sre/failure-modes.md, sre/query-patterns.md]
---
How Axiom is reached: `search_logs` reads the logs dataset the connection was set up with, and `search_traces` and `search_errors` its traces dataset, for a service on the resource map by its service.name. `querydataset` runs any APL on any dataset, including services that are not on the map, and its answer links to the same query in Axiom, which goes in your answer.

1. Call `checkmonitors` for the monitors and whether each is alerting now, then `getmonitorhistory` for when the one that matters began to fire. A monitor's query says what it measured.
2. When you do not know where a service's data is, `listdatasets` lists the datasets and `getdatasetfields` the fields of one, so a query names fields that exist.
3. Call `search_errors` for the failing operations of the service and when each began, and `search_logs` with the text of an error for the lines around it.
4. Call `search_traces` for the slowest and failed requests. Then load the skill that fits: axiom_errors for failing requests, axiom_latency for slow ones.
