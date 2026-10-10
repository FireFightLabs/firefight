json.id page.id
json.title page.title
json.kind page.kind
json.position page.position
json.url page.url
json.text page.text if local_assigns[:full]
json.wording_id page.current_wording&.id
json.incident_role page.current_wording&.directing_role&.slug if page.directing?
json.freeze_windows page.freeze_rules.map(&:stored) unless page.directing?
json.source page.source ? { kind: page.source.kind, label: page.source.label, url: page.source_url } : nil
json.updated_at page.current_wording&.created_at&.utc&.iso8601
