# A workspace's first run. Progress is read off the first test incident,
# never stored. Stored: the welcome message id, the last coaching step
# posted, dialog dismissal, completion.
class WorkspaceOnboarding < ApplicationRecord
  # Shared by the Slack welcome message and the dashboard dialog.
  STEPS = [
    { title: "Declare an incident.", detail: "Firefight opens a channel for it and announces it in #incidents" },
    { title: "Work it in that channel.", detail: "Set a lead, post what is happening" },
    { title: "Resolve it.", detail: "Firefight drafts the postmortem for you" }
  ].freeze

  # Events that can move the first test incident a stage on.
  PROGRESS_EVENTS = [
    IncidentEvent::INCIDENT_CREATED,
    IncidentEvent::LEAD_ASSIGNED,
    IncidentEvent::INCIDENT_RESOLVED,
    IncidentEvent::INCIDENT_CANCELED,
    IncidentEvent::POSTMORTEM_GENERATED
  ].freeze

  # How far the first test incident has got. Every surface reads this.
  STAGE_NONE = 0
  STAGE_DECLARED = 1
  STAGE_LED = 2
  STAGE_MESSAGED = 3
  STAGE_RESOLVED = 4
  STAGE_DONE = 5

  belongs_to :workspace
  belongs_to :installer, class_name: "WorkspaceMembership", optional: true

  def first_incident
    workspace.incidents.tests.order(:sequence_number).first
  end

  def tracks?(incident)
    incident.first_test_in_workspace?
  end

  def stage
    incident = first_incident
    incident ? stage_of(incident) : STAGE_NONE
  end

  # A canceled incident counts as done. There is nothing to write up.
  def stage_of(incident)
    return STAGE_DONE if incident.canceled? || (incident.postmortem.present? && !incident.postmortem.generating?)
    return STAGE_RESOLVED if incident.closed?
    return STAGE_MESSAGED if incident.incident_transcript_messages.kept.exists?
    return STAGE_LED if incident.lead.present?

    STAGE_DECLARED
  end

  # The dialog only needs to get the first test incident declared.
  def dialog_pending_for?(membership)
    return false if dialog_dismissed_at.present?
    return false unless installer.present? && installer == membership

    first_incident.nil?
  end

  def dismiss_dialog!
    update!(dialog_dismissed_at: Time.current) if dialog_dismissed_at.nil?
  end

  def complete!
    update!(completed_at: Time.current) if completed_at.nil?
  end
end
