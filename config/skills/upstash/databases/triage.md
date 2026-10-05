---
name: upstash_triage
when: Starting on anything wrong with Upstash, such as a Redis database that is slow, refuses commands or is unreachable, or QStash messages and workflows that fail, before knowing what kind of problem it is
tools: [resource_status, query_metrics, search_logs, search_errors, redis_list_databases, qstash_list_users]
references: [redis/error-handling.md, qstash/dlq.md]
---
A Redis database is on the resource map by its name, and the QStash of each region as QStash eu or QStash us. `resource_status` and `query_metrics` read a Redis database, and `search_logs` and `search_errors` read the delivery logs and the dead letter queue of a region's QStash. Upstash's own tools take a region, and a service of qstash or workflow, for QStash and Workflow. Never ask a tool for credentials, and never run a Redis command that changes data.

1. When the person did not name the database, call `redis_list_databases`. For QStash, `qstash_list_users` with each region shows whether it is in use.
2. For Redis, call `resource_status`. Its state says whether it is active, and its limits say how many clients, commands per second and how large a request it takes. Then load the upstash_redis skill.
3. For QStash, call `search_errors` for the region, which groups what reached the dead letter queue by where it was going and what came back. Then load the upstash_qstash skill, or upstash_workflow for a workflow.
