---
name: setup
when: Setting up Firefight, or changing its severities, statuses, types, roles or workspace settings
tools: [get_workspace_config, list_integrations, upsert_severity, upsert_status, upsert_incident_type, upsert_incident_role, update_workspace_settings]
---
1. Call `get_workspace_config` first. It holds every severity, status, type and role, the alert sources and the settings.
2. Go one step at a time. Offer the most useful missing piece, where alerts come from, then code, then the rest, and change a setting only once the person agrees to it.
3. To connect something, ask which kind they want and show it with `list_integrations`. They connect from the table it draws. Never ask for or repeat a key, token or password.
4. Change one entry per call with `upsert_severity`, `upsert_status`, `upsert_incident_type` or `upsert_incident_role`. Pass `slug` to change an existing one and leave it out to create. `position` 1 is first, and for a severity first is the most severe. A new status needs its `lifecycle_stage`.
5. `update_workspace_settings` takes only the settings that change.
