---
name: mixpanel_feature_flags
when: Finding which Mixpanel feature flag changed before an incident, and turning a flag off when it is the cause
tools: [get_audit_log, list_feature_flags, get_feature_flag, get_events, run_query, update_feature_flag]
references: [feature-flags/SKILL.md, feature-flags/lifecycle-and-state-machine.md, feature-flags/staged-rollout.md, feature-flags/experiment-linked-flags.md, feature-flags/sdk-and-exposure.md]
---
1. Call `get_audit_log` for the project over the day before the incident for flags enabled, ramped or edited, with who did it. It needs an organization admin or owner, and is in beta for some organizations, so when it is refused say so and go on.
2. Call `list_feature_flags` and find the flag by its key or name, then `get_feature_flag` for its state, rollout and targeting. A flag owned by an experiment is changed through the experiment, since a direct change is overwritten.
3. Check the flag is the cause before blaming it. The SDK sends an exposure event, with the flag key and the variant each user got, each time it reads the flag. Find it with `get_events`, then `run_query` it grouped by variant next to the event that broke. A problem only among users on the new variant points at the flag.
4. Turning it off is a change for the fix, never part of the investigation. The kill switch is disabling the flag, not setting its rollout to zero. Call `update_feature_flag` with only its `status` set to disabled, which leaves the rollout as it was. Sending other fields with it goes through Mixpanel's general update instead, which refuses a flag with several rollout groups. Disabling alone is safe on any flag.
5. The undo is `update_feature_flag` with only its `status` set to enabled, which serves the same rollout again.
