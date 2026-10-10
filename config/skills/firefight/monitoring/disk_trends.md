---
name: disk_trends
when: A scheduled check of disk space, or anyone asking whether a disk, volume or database is filling up and when it will be full
tools: [list_notices, find_resources, get_resource, query_metrics, resource_status]
---
1. List what holds data with `find_resources`, passing `kind` database, virtual_machine, service and cluster, or the `catalog_entry` the check's notes name. Read every one, not only the first.
2. For each, read its disk over the last two weeks with `query_metrics` and `metrics` disk, passing `minutes` 20160. Where the provider keeps no disk metric, `resource_status` often names the size and how much is used.
3. Work out the rate from the first and last readings and the readings between, not from one day. A volume that grows in steps, such as after a nightly import, grows at the rate of its steps. Say how sure you are when the rate is uneven.
4. From the rate, the day it reaches 100%. Raise it when it is full within 60 days, as medium within 30 days and high within 7, or already above 90%. A disk that grows by itself to a larger size, such as one with storage autoscaling, is a problem only when it nears that limit, which `resource_status` names.
5. Read `list_notices` with `signal` disk first, and keep the topic and resource of anything raised before, so the same disk is the same problem.
6. A disk the check could not read is a gap to say, never a disk that is fine.
