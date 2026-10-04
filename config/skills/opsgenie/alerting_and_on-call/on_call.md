---
name: opsgenie_on_call
when: Finding who is on call in Opsgenie, or who an alert reaches next through its escalation
tools: [who_is_on_call, list_escalations]
---
1. Call `who_is_on_call` for every schedule, or with `schedule` for one by its name. Each schedule says the team that owns it.
2. Call `list_escalations` for who each escalation policy notifies, in what order, after how many minutes and on which condition, such as if-not-acked. The schedule a rule names is answered by `who_is_on_call`, and next means the person after the one on call now.
3. Name who is on call first, then who an unacknowledged alert reaches next and when.
