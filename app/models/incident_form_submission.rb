# Shared by Slack and the dashboard so the translation from a submitted form
# to what the lifecycle service wants is written once.
class IncidentFormSubmission
  TERMINAL_SCOPE = {
    IncidentForm::SLUG_RESOLVE => :closed,
    IncidentForm::SLUG_CANCEL => :canceled
  }.freeze

  def initialize(workspace, incident:, form_slug:, system_attrs:, custom_fields: {}, visible_system_keys: nil)
    @workspace = workspace
    @incident = incident
    @form_slug = form_slug
    @system_attrs = (system_attrs || {}).stringify_keys
    @custom_fields = custom_fields || {}
    @visible_system_keys = visible_system_keys
  end

  def attributes
    attrs = { incident_status: status }
    attrs[:incident_severity] = severity if severity
    attrs[:name] = value(IncidentSystemField::KEY_NAME) if value(IncidentSystemField::KEY_NAME).present?
    attrs[:summary] = value(IncidentSystemField::KEY_SUMMARY) if value(IncidentSystemField::KEY_SUMMARY).present?
    attrs[:incident_type] = incident_type if offered?(IncidentSystemField::KEY_INCIDENT_TYPE)
    attrs[:custom_fields] = @custom_fields if @custom_fields.present?
    attrs.merge(next_update_attributes)
  end

  # A declare has no incident to fall back on, so every value comes from the
  # form and the status is the workspace default.
  def creation_attributes
    {
      incident_status: @workspace.incident_statuses.default_status,
      incident_severity: severity,
      incident_type: incident_type,
      name: value(IncidentSystemField::KEY_NAME),
      summary: value(IncidentSystemField::KEY_SUMMARY),
      custom_fields: @custom_fields.presence || {},
      # Absent when the field is not on the form, which means public.
      is_private: value(IncidentSystemField::KEY_VISIBILITY) == Incident::VISIBILITY_PRIVATE
    }
  end

  # A cancel has no message field, so the summary typed while cancelling stands in.
  def message
    return value(IncidentSystemField::KEY_MESSAGE).presence if @form_slug == IncidentForm::SLUG_UPDATE
    return value(IncidentSystemField::KEY_SUMMARY).presence if @form_slug == IncidentForm::SLUG_CANCEL

    nil
  end

  # A platform user id from Slack, a membership id from the dashboard. Each
  # entry point resolves its own.
  def lead_value
    value(IncidentSystemField::KEY_LEAD).presence
  end

  private

  # Falls back to the first status in the target stage when the form never
  # offered the choice.
  def status
    scope = terminal_scope
    return chosen_status || @incident.incident_status unless scope

    # first! because a workspace with no status in the target stage cannot
    # complete this transition, and the caller renders the raise.
    chosen_status(scope) || scope.first!
  end

  def terminal_scope
    stage = TERMINAL_SCOPE[@form_slug]
    return nil unless stage

    @workspace.incident_statuses.public_send(stage).active.ordered
  end

  def chosen_status(scope = @workspace.incident_statuses.active)
    slug = value(IncidentSystemField::KEY_STATUS)
    return nil if slug.blank?

    scope.find_by(slug: slug)
  end

  def severity
    slug = value(IncidentSystemField::KEY_SEVERITY)
    return nil if slug.blank?

    @workspace.incident_severities.active.find_by!(slug: slug)
  end

  # Blanking a field that was on the form clears the attribute. A field never
  # on the form leaves what the incident already holds.
  def offered?(key)
    return value(key).present? if @visible_system_keys.nil?

    @visible_system_keys.include?(key)
  end

  def incident_type
    slug = value(IncidentSystemField::KEY_INCIDENT_TYPE)
    return nil if slug.blank?

    @workspace.incident_types.active.find_by!(slug: slug)
  end

  # Absent leaves next_update_at alone, present but blank clears it. Written with the status,
  # since Incident::Lifecycle clears it for a terminal stage in the same save and a later write would undo that.
  def next_update_attributes
    return {} unless offered?(IncidentSystemField::KEY_NEXT_UPDATE)

    minutes = value(IncidentSystemField::KEY_NEXT_UPDATE)
    { next_update_at: minutes.present? ? Time.current + minutes.to_i.minutes : nil }
  end

  def value(key)
    @system_attrs[key]
  end
end
