---
name: opsgenie_triage
when: Finding out what Opsgenie is alerting on, what an Opsgenie alert holds, or which Opsgenie incidents are open
tools: [search_alerts, get_alert, search_incidents]
---
1. Call `search_alerts` with `query` status: open for what is firing now, newest first. Each alert has its tiny id, priority, how many times it fired and whether someone acknowledged it. Add AND acknowledged: false for the ones nobody has taken, or message: with words from the problem to narrow it.
2. An alert that fired many times or keeps coming back is flapping or ongoing. Many alerts from one entity or source point at that system.
3. Call `get_alert` for the one that matters, by its tiny id with `identifier_type` tiny. Its description and details say what the monitoring tool saw, its notes what responders wrote, and its log who was notified and who acknowledged it.
4. Call `search_incidents` with `query` status: open for incidents in Opsgenie and the services they affect.
5. Tell the person what is alerting, since when, how often, and who has it.
