# The follow-ups already on the incident, built from its records so none is left out or reworded by the model.
module Postmortem::FollowUpsSection
  STATUS_WORDS = {
    IncidentAction::STATUS_OPEN => "open",
    IncidentAction::STATUS_IN_PROGRESS => "in progress",
    IncidentAction::STATUS_DONE => "done"
  }.freeze

  def self.markdown(incident)
    incident.incident_actions.active.followups.includes(:assignee).order(:created_at).map { |action| line(action) }.join("\n")
  end

  def self.line(action)
    text = "- #{escaped(action.description)}"
    if action.external_url.present?
      text += " ([#{escaped(action.external_key.presence || action.external_url)}](<#{action.external_url}>))"
    end
    status = STATUS_WORDS.fetch(action.status, action.status)
    status += ", #{action.assignee.actor_display_name}" if action.assignee && !action.done?
    "#{text}, #{status}"
  end

  # A description is plain text, so markdown it happens to hold is shown as typed.
  def self.escaped(text) = text.to_s.squish.gsub(/([\\`*_\[\]<>#])/, "\\\\\\1")
  private_class_method :line, :escaped
end
