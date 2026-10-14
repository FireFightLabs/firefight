---
name: deploying
when: Before, during or after a release or deploy, judging whether a release caused a problem, rolling one back or fixing forward, or following a pipeline to its end
tools: [recent_deploys, run_history, what_changed, resource_status, run_key_query, rollback]
---
What good looks like: a release is safe when you can see it working and can undo it. Changes go out in small steps, each watched long enough to trust, with a rollback path known before it is needed.

How to approach it:
1. Before a release, know what changes, which services and data it touches, and whether a rollback stays possible. Database migrations are the usual reason it does not: a renamed or dropped column breaks the old version. When the team has a saved runbook for the release, the running_runbooks skill runs it.
2. Release in steps when the platform allows it (a canary, one region, a percentage). The handbook names any freeze window, and a plan timed inside one is refused, so say when one applies.
3. Watch the signals that would show harm: `run_key_query` for error rate and latency against normal for this time of day, the key business action, and the logs of what changed.
4. When a release looks bad, first ask whether it is the cause. `what_changed` puts the deploys, settings, hand edits and changes made through Firefight in one list. What else changed in the same window: config, a dependency, a firewall rule, traffic? Check the strongest alternative before you blame the release. A deploy carries every commit since the one before it, while a deploy list names it by its newest commit alone, so read what it carried (`recent_deploys` says so where a code host holds the repository) and name the change in it that explains the symptom before you blame it. A release that changed only tests or docs did not change how production behaves.
5. If it is the cause, a `rollback` is usually the fastest safe fix, unless a migration makes the old version incompatible. Then fix forward, or roll back only the part that is safe. Know what a rollback undoes before you offer one: every change since the version it goes back to, which can be many releases and their migrations. Say that with the offer, and when it is wide, prefer reverting the one change that caused it.
6. Follow the whole release, every stage of the pipeline or workflow, and name the step that failed with its own log. `run_history` follows a run by its id, and a watch (the watching skill) follows it after you answer.

What to check:
- The run's stages and which one failed, with its log.
- The migrations in the release and whether they can be reversed.
- What else changed in the same window across the workspace.
- Whether the new version is actually serving, not only built: `resource_status` and `recent_deploys` say what runs now.

Trade-offs:
- A rollback is fast but can lose a fix that was also in the release. Say what would be lost.
- Fixing forward is slower but keeps data compatible after a migration.

Done means: the new version serves, the signals look normal for long enough, and anyone waiting knows. Or the release is rolled back or paused with the reason, and the person who owns it knows the next step.

Proactive habits:
- Learn how long each release usually takes and say when one runs long.
- Flag a risky change before it ships: a migration without a lock timeout, a change to a service with recent incidents.
