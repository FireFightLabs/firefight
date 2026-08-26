# What a submitted lifecycle form means for the incident.
#
# A form submission arrives as slugs and strings, keyed by system field key.
# The lifecycle service wants records. That translation is the same whoever
# submitted it, so it lives here rather than in the Slack handler that used to
# own it and the dashboard controller that would otherwise have copied it.
#
# Each entry point still owns its own input shape. Slack reads Block Kit state
# and resolves a lead from a platform user id, the dashboard posts JSON and
# resolves a lead from a membership id. Both arrive here holding the same two
# validated hashes and get the same answer.
class IncidentFormSubmission
  # Which stage a form's transition targets, and so which statuses the picked
  # one is allowed to come from.
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

  # The attributes hash for IncidentLifecycleService#change_status.
  def attributes
    attrs = { incident_status: status }
    attrs[:incident_severity] = severity if severity
    attrs[:name] = value(IncidentSystemField::KEY_NAME) if value(IncidentSystemField::KEY_NAME).present?
    attrs[:summary] = value(IncidentSystemField::KEY_SUMMARY) if value(IncidentSystemField::KEY_SUMMARY).present?
    attrs[:incident_type] = incident_type if offered?(IncidentSystemField::KEY_INCIDENT_TYPE)
    attrs[:custom_fields] = @custom_fields if @custom_fields.present?
    attrs.merge(next_update_attributes)
  end

  # The attributes hash for IncidentLifecycleService#create. A declare has no
  # incident to fall back on, so every value comes from the form, and the
  # status is the workspace's default rather than anything a responder picked.
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

  # The sentence the channel sees with the change. The update form asks for it
  # outright. A cancel has no message field, so the summary a responder typed
  # while cancelling is the explanation of why, and stands in for one.
  def message
    return value(IncidentSystemField::KEY_MESSAGE).presence if @form_slug == IncidentForm::SLUG_UPDATE
    return value(IncidentSystemField::KEY_SUMMARY).presence if @form_slug == IncidentForm::SLUG_CANCEL

    nil
  end

  # The raw value of the lead field, which is a platform user id from Slack and
  # a membership id from the dashboard. Each entry point resolves its own,
  # since only it knows which it is holding.
  def lead_value
    value(IncidentSystemField::KEY_LEAD).presence
  end

  private

  # A terminal form honours the status a responder picked when the workspace
  # offers more than one, and falls back to the first in the target stage when
  # the form never offered the choice.
  def status
    scope = terminal_scope
    return chosen_status || @incident.incident_status unless scope

    # first! rather than first. A workspace with no status in the target stage
    # cannot complete this transition at all, and the caller renders the raise
    # as the sentence saying so.
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

  # Blanking a field that was on the form clears the attribute. A field that
  # was never on the form leaves what the incident already holds, which is why
  # this asks whether it was offered rather than only whether it has a value.
  # A caller that does not track visibility falls back to the value, which is
  # the same answer whenever the field was answered.
  def offered?(key)
    return value(key).present? if @visible_system_keys.nil?

    @visible_system_keys.include?(key)
  end

  def incident_type
    slug = value(IncidentSystemField::KEY_INCIDENT_TYPE)
    return nil if slug.blank?

    @workspace.incident_types.active.find_by!(slug: slug)
  end

  # A workspace that took Next Update off its form has opted out of reminders,
  # so the field being absent leaves next_update_at alone. On the form but
  # unanswered clears it. It rides along with the status rather than being
  # written afterwards, so a terminal status wins. Incident::Lifecycle clears
  # next_update_at in the same save, and a later write would undo it.
  def next_update_attributes
    return {} unless offered?(IncidentSystemField::KEY_NEXT_UPDATE)

    minutes = value(IncidentSystemField::KEY_NEXT_UPDATE)
    { next_update_at: minutes.present? ? Time.current + minutes.to_i.minutes : nil }
  end

  def value(key)
    @system_attrs[key]
  end
end
