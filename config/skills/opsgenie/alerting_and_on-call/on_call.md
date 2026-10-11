---
name: opsgenie_on_call
when: Finding who is on call in Opsgenie, who comes on next, who an alert reaches next through its escalation, or putting someone else on call for a while
tools: [who_is_on_call, who_is_on_call_next, list_escalations, create_schedule_override]
---
1. Call `who_is_on_call` for every schedule, or with `schedule` for one by its name. Each schedule says the team that owns it.
2. Call `who_is_on_call_next` with the schedule for who takes over next, overrides counted.
3. Call `list_escalations` for who each escalation policy notifies, in what order, after how many minutes and on which condition, such as if-not-acked. The schedule a rule names is answered by `who_is_on_call`.
4. Name who is on call first, then who an unacknowledged alert reaches next and when.
5. When the person on call is out and someone covers, call `create_schedule_override` with the schedule, the person covering by their email, and when it starts and ends. Say exactly what will change first. The person confirms the call.
