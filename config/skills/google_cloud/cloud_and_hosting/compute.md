---
name: google_cloud_compute
when: A Compute Engine instance is down, unreachable, not booting, or overloaded
tools: [resource_status, query_metrics, search_logs, restart]
references: [compute/vm-startup.md, compute/serial-console.md, compute/reset-instance.md]
---
1. Call `resource_status` for its state, machine type and addresses. Terminated or stopped means it is not running at all, and Google's status message says why when it has one.
2. Call `query_metrics` with `metrics` cpu, network_in and network_out. memory needs Google's Ops Agent on the instance, so no data for it does not mean zero.
3. Read its logs with `search_logs`, such as the serial port output and the agent's lines, for a boot that failed, a full disk or a crash.
4. A boot that fails usually needs the boot disk repaired from another instance, which is a step for a person, as Google's guide on boot disks describes.
5. A reset with `restart` is a hard reset: the instance starts again from its disk, without shutting down its operating system, and what was in its memory is lost. Offer it only for an instance that is hung and not answering, and say what is lost. There is no undo.
6. Say what is wrong, the evidence, and the fix.
