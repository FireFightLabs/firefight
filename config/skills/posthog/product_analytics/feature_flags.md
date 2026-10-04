---
name: posthog_feature_flags
when: Finding which PostHog feature flag changed before an incident, who it reaches, and turning a flag off when it is the cause
tools: [advanced_activity_logs_list, feature_flags_activity_retrieve, feature_flag_get_all, feature_flag_get_definition_by_key, feature_flags_dependent_flags_retrieve, scheduled_changes_list, query_trends, feature_flag_disable, feature_flag_enable]
references: [feature-flags/api.md, feature-flags/best-practices.md]
---
1. Call `advanced_activity_logs_list` with `scopes` FeatureFlag, a `start_date` a day or more before the incident and an `end_date` at its start. Leave detail.changes out of `fields` at first and ask for it only on the entries that matter, since it holds every changed value. A rollout raised, a release condition widened, or a flag switched on shortly before the problem is the first suspect.
2. For one flag, `feature_flags_activity_retrieve` with its `id` gives every change with who made it and the value before and after. `scheduled_changes_list` shows changes PostHog made on a schedule, which no person made at that moment.
3. Call `feature_flag_get_definition_by_key` with the flag's `key` for its rollout, conditions, variants and what is linked to it: experiments, surveys and early access features. `feature_flag_get_all` with `search` finds a flag by part of its key or name.
4. Check the flag is the cause before blaming it. Call `query_trends` on the event that broke with a `breakdownFilter` on the event property $feature/<the flag key>, or on $feature_flag_called filtered to that flag and broken down by $feature_flag_response. Errors or drops only where the flag is on point at it.
5. Turning it off is a change for the fix, never part of the investigation. `feature_flag_disable` takes the flag's numeric `id`, sets it off and changes nothing else, so every caller falls back to its own default. Say first what else it affects. Linked experiments and surveys stop, and any flag that depends on it (`feature_flags_dependent_flags_retrieve`) makes PostHog refuse the change until that one is handled. PostHog can also hold the change for its own approval.
6. The undo is `feature_flag_enable` with the same `id`, which puts the flag back as it was, since disabling kept its rollout.
