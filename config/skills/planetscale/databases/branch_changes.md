---
name: planetscale_branch_changes
when: A PlanetScale branch may be undersized, was just resized or reconfigured, or its CPU, memory or disk is high, or the person wants it resized or its production status changed
tools: [query_metrics, run_history, planetscale_list_branch_changes, scale, planetscale_resize_branch, planetscale_promote_branch, planetscale_demote_branch]
---
1. Call `query_metrics` for the database or branch with `metrics` cpu, memory and disk, over the time the problem covers. A Postgres branch's are percentages of its cluster, and a Vitess one's are its primary tablet's.
2. Call `run_history` with `name` resize for the changes made to the branch's size and settings, newest first, with who made each and what it changed from and to. A resize or a configuration change just before the problem is a suspect, and one still going explains a slow period.
3. `planetscale_list_branch_changes` reads the same with a Vitess keyspace's own resizes when given `keyspace`.
4. When the person agrees to a bigger size:
   - A Postgres branch: `scale` with `plan` set to the cluster size, as planetscale_list_cluster_sizes names it, and `instances` for the replicas in all.
   - A Vitess database is sized per keyspace, so call `planetscale_resize_branch` with `keyspace`, `cluster_size` and `extra_replicas`, or `vtgate_size` and `vtgate_count` for its VTGates.
5. `planetscale_promote_branch` makes a development branch a production branch, and `planetscale_demote_branch` makes a production branch a development branch again. Each changes how the branch takes schema changes, so ask first.
