---
name: aws_ec2
when: Finding why an EC2 instance is unreachable, failing its status checks, stopped or overloaded
tools: [resource_status, query_metrics, cloudwatch_metrics, logs_insights_query]
references: [compute/troubleshooting.md, compute/auto-scaling.md]
---
1. Call `resource_status`. Read its state and the two status checks. The system check watches the AWS host, its power and network, and the instance check watches the instance's own operating system and network setup. A scheduled event, such as a retirement or a reboot, is listed with when it starts.
2. Match the cause:
   - System check impaired: the host has a problem. Stopping and starting an EBS backed instance moves it to new hardware, where a reboot stays on the same host.
   - Instance check impaired: the operating system is in trouble, such as a full disk, exhausted memory, a kernel that does not boot or a broken network setup. A reboot can bring it back, and the cause is inside the instance.
   - Stopped or terminated by surprise: the state reason says why, such as a Spot interruption, a shutdown from inside, or an Auto Scaling group replacing it after a failed health check.
3. Call `query_metrics` over the window with `metrics` cpu, network_in and network_out, and `cloudwatch_metrics` for StatusCheckFailed over time. CloudWatch has no memory or disk use for an instance unless the CloudWatch agent sends them. A burstable instance (T family) slows down once it runs out of CPU credits, which looks like CPU held at its baseline.
4. The instance's own logs reach CloudWatch Logs only through the CloudWatch agent. When it sends them, read them with `logs_insights_query` on the agent's log group.
5. Stopping, starting or rebooting an instance is a step for a person in the AWS console, since it interrupts whatever the instance runs. Say which and why, and that an instance store volume loses its data on a stop.
