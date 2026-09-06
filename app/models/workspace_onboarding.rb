# A workspace's first run. How far it has got is read off the first test
# incident rather than stored, so a step can never be ticked without the
# thing having happened. What is stored is what the incident cannot know:
# the welcome message to update, the last coaching step posted, whether the
# installer has seen the dialog, and when the loop was closed.
class WorkspaceOnboarding < ApplicationRecord
  # The three steps, worded once for the Slack welcome message and the
  # dashboard dialog alike.
  STEPS = [
    { title: "Declare an incident.", detail: "Firefight opens a channel for it and announces it in #incidents" },
    { title: "Work it in that channel.", detail: "Set a lead, post what is happening" },
    { title: "Resolve it.", detail: "Firefight drafts the postmortem for you" }
  ].freeze

  # The events that can move the first test incident a stage on.
  PROGRESS_EVENTS = [
    IncidentEvent::INCIDENT_CREATED,
    IncidentEvent::LEAD_ASSIGNED,
    IncidentEvent::INCIDENT_RESOLVED,
    IncidentEvent::INCIDENT_CANCELED,
    IncidentEvent::POSTMORTEM_GENERATED
  ].freeze

  # How far the first test incident has got, as one number every surface
  # reads: the welcome checklist, the coach in the channel, and the dialog.
  STAGE_NONE = 0
  STAGE_DECLARED = 1
  STAGE_LED = 2
  STAGE_MESSAGED = 3
  STAGE_RESOLVED = 4
  STAGE_DONE = 5

  belongs_to :workspace
  belongs_to :installer, class_name: "WorkspaceMembership", optional: true

  # The workspace's first test incident, which is what the welcome message's
  # declare button and the dashboard dialog create.
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

  # A canceled first incident ends the loop early. There is nothing to write
  # up, so it counts as done rather than waiting forever.
  def stage_of(incident)
    return STAGE_DONE if incident.canceled? || (incident.postmortem.present? && !incident.postmortem.generating?)
    return STAGE_RESOLVED if incident.closed?
    return STAGE_MESSAGED if incident.incident_transcript_messages.kept.exists?
    return STAGE_LED if incident.lead.present?

    STAGE_DECLARED
  end

  # The dialog exists to get the first test incident declared. Once one
  # exists, from any surface, there is nothing left for it to say.
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
