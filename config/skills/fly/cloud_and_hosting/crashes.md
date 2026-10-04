---
name: fly_crashes
when: Machines of a Fly.io app keep stopping, restarting or running out of memory, or the app went down without a deploy
tools: [resource_status, query_metrics, search_logs, recent_deploys]
references: [machines/restart-policy.md, machines/machine-states.md, deploy/troubleshooting.md]
---
1. Call `resource_status`. Each machine's latest events say how it last stopped: an exit with its code, whether it ran out of memory, a signal, and how many times it has been restarted.
2. Ran out of memory: call `query_metrics` with memory and cpu over the hours before. Memory that climbs steadily until the exit is a leak, and memory that jumps with traffic is a machine too small for its load. Fly's kernel prints a line saying it killed the process for running out of memory, which `search_logs` with `text` set to Out of memory finds. Raising the machine's memory is a step for a person, done in Fly.io, since Halon cannot resize a machine.
3. A non-zero exit code: read `search_logs` just before each exit for the error the app printed. The same error each time is a bug or a missing dependency, often something the app calls that went away.
4. Restarts that stopped: with the on-failure policy Fly restarts a machine up to its number of tries (10 by default) within a few minutes, and then leaves it stopped. A machine that stays stopped after a run of exits has used its tries, and Fly's proxy then reports it has no healthy machine to send traffic to. With the always policy Fly keeps restarting it.
5. A machine stopped with no exit of its own may have been stopped by Fly's proxy for spare capacity, when the app stops machines automatically. That is normal. It becomes a problem only when nothing starts them again, which the fly_proxy_errors skill covers.
6. When the crashes began with a release, check `recent_deploys`. A rollback, from the fly_fixes skill, is the quick way back. When the code is fine and a machine is stuck, a restart may be enough.
