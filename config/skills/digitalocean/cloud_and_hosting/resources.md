---
name: digitalocean_resources
when: An App Platform app is slow, runs out of CPU or memory, or needs more or fewer instances
tools: [resource_status, query_metrics, resource_metrics, scale_app, scale]
references: [shared/AppSpec-Reference.md]
---
1. Call `resource_status`. Note each component's instance count and size, and whether it autoscales, which shows as a range of instances.
2. Call `query_metrics` with `metrics` set to cpu and memory over a window long enough to see the trend. Each instance is its own series, so one hot instance among cool ones points at uneven load, not a size problem.
3. CPU near 100% across every instance means the component needs more instances or a larger size. Memory climbing steadily until restarts means a leak, which more instances only delay, so read `resource_metrics` with `metrics` set to restarts before scaling.
4. To add instances to a component, propose `scale` for an app with one service or worker, or `scale_app` with the `component` and `instances` when it has several. The rest of the app's spec stays as it is and the same code is redeployed. A component that autoscales is refused, since its count is set by its autoscaling range in the control panel.
5. A larger instance size is a change to the app's spec that Halon does not make. Say which size the metrics point at and leave it to the person in the control panel.
