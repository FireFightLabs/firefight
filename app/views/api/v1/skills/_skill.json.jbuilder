json.id skill.id
json.name skill.name
json.when skill.live_version.used_when
json.enabled skill.enabled?
json.version skill.live_version.number
json.version_id skill.live_version.id
json.copy_of skill.library_name
json.workflows_running_it skill.usage_count
json.tools skill.live_version.tools if local_assigns[:full]
json.steps skill.live_version.steps if local_assigns[:full]
json.updated_at skill.live_version.created_at.utc.iso8601
