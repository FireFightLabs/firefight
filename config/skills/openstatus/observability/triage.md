---
name: openstatus_triage
when: Finding whether a site or endpoint OpenStatus monitors is down, slow, or failing from some regions
tools: [resource_status, list_monitors, get_monitor_status, get_monitor_summary, list_response_logs, get_response_log]
---
How OpenStatus is reached: `resource_status` asks the OpenStatus monitor that checks a hostname on the resource map, or a hostname the map says a service serves, how it stands in each region. OpenStatus's own tools reach every monitor in the workspace. Each answer about a monitor links to its page in OpenStatus, which goes in your answer.

1. Call `resource_status` for the hostname, or `list_monitors` and then `get_monitor_status` with the monitor's id when the monitor checks something that is not on the map. A region in error or degraded while others are active is a regional problem, every region failing is an outage.
2. Call `get_monitor_summary` with a time range of 1d for how many checks passed, degraded or failed, and the latency percentiles from p50 to p99.
3. Call `list_response_logs` for the failed and degraded checks, from before the problem began. Each check gives its status code, its latency and its timing (dns, connect, tls, time to first byte, transfer), so a slow tls or dns lookup points away from the app.
4. Call `get_response_log` for one failed check to read its status code, headers and the start of the body, which is kept for failed and degraded checks.
5. Say since when it fails, from which regions, with what status code, and where the time went.
