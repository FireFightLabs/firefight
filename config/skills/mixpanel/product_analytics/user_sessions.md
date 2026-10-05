---
name: mixpanel_user_sessions
when: Seeing what one user did in Mixpanel around an incident they reported, from their events and session replays
tools: [get_user_replays_data, run_query, get_events]
references: [reports/read-flows.md]
---
1. Ask for the user's Mixpanel distinct ID, or the email or ID the product uses for them, when the person has not given it.
2. Call `get_user_replays_data` for that user. It returns their replays next to their events, so you see the steps before the failure and whether they retried, gave up or left.
3. Compare with everyone else. `run_query` for the same events by hour across all users shows whether this user's experience is the incident or an exception to it.
4. Never paste a user's personal data into the incident. Name the steps they took and where it failed.
