---
name: northflank_resources
when: Checking whether a Northflank service or database is short of CPU, memory or disk, or needs more instances
tools: [resource_status, query_metrics, list_containers, search_logs]
---
1. Call `resource_status` for the plan and instances of a service, or the plan, replicas and storage of a database.
2. Call `query_metrics` with `metrics` cpu and memory, and disk for a database, over a range long enough to show the normal level before the problem. Each container is its own series, so one container near its limit shows even when the others look fine.
3. Read it against the plan:
   - Northflank's alerts count 90% for a short while as a spike and 90% for 5 minutes as sustained. Sustained is what hurts.
   - CPU and memory rising with requests means the service needs a bigger plan or more instances.
   - Memory rising steadily while traffic is flat, and dropping only when a container restarts, is a leak in the code. More memory only delays it.
   - A database past half its storage should grow before it fills. Storage and replicas of a database can only be increased, never reduced.
4. Memory that drops to zero with a new container in `list_containers` right after is a restart. Read what it printed just before with `search_logs`.
5. Say which resource is short, how close to its limit it came and when, and whether traffic explains it.
