---
name: digitalocean_droplets
when: A Droplet (a DigitalOcean virtual machine) is down, unreachable, slow, full or needs a reboot
tools: [list_resources, resource_status, query_metrics, restart]
references: [troubleshooting/networking-issues.md]
---
1. Call `resource_status`. Its status says whether it runs (active) or is powered off (off), and a locked Droplet is in the middle of an action DigitalOcean is running, so wait for it rather than act.
2. Call `query_metrics` with `metrics` set to cpu, memory and disk. Disk near 100% stops databases and logs from writing, memory near 100% makes the kernel kill processes, and both outlast a reboot. network_in and network_out show traffic on the public interface, in megabits per second. cpu and network are always there, but memory and disk come only from the DigitalOcean metrics agent, so a Droplet without it has no data for them.
3. What runs on a Droplet is the team's own, and Firefight cannot read its logs. Say what the metrics show and what to check on the machine.
4. Only for a Droplet that hangs while its disk and memory are fine, propose `restart`, which reboots it gracefully, as the reboot command on the machine would, and the person confirms it first. It does not fix a full disk or a runaway process that starts again at boot.
