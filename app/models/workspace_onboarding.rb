# A workspace's first run. Progress is read off the first test incident
# rather than stored, so a step can never be ticked without the thing having
# happened. What is stored is what the incident cannot know: the welcome
# message to update, whether the installer has seen the dialog, and when the
# loop was closed.
class WorkspaceOnboarding < ApplicationRecord
  # The three steps, worded once for the Slack welcome message and the
  # dashboard dialog alike.
  STEPS = [
    { title: "Declare an incident.", detail: "Firefight opens a channel for it and announces it in #incidents" },
    { title: "Work it in that channel.", detail: "Set a lead, post what is happening" },
    { title: "Resolve it.", detail: "Firefight drafts the postmortem for you" }
  ].freeze

  # The events that can move a step. The subscriber ignores everything else.
  PROGRESS_EVENTS = [
    IncidentEvent::INCIDENT_CREATED,
    IncidentEvent::LEAD_ASSIGNED,
    IncidentEvent::INCIDENT_RESOLVED,
    IncidentEvent::INCIDENT_CANCELED,
    IncidentEvent::POSTMORTEM_GENERATED
  ].freeze

  Progress = Struct.new(:declared, :lead_set, :resolved, :written_up, :write_up_dropped, keyword_init: true) do
    def self.none
      new(declared: false, lead_set: false, resolved: false, written_up: false, write_up_dropped: false)
    end

    def complete?
      declared && lead_set && resolved && (written_up || write_up_dropped)
    end
  end

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

  # A canceled first incident still counts as taking the loop to its end.
  # There is nothing to write up, so that step is dropped rather than left
  # waiting forever.
  def progress
    incident = first_incident
    return Progress.none unless incident

    Progress.new(
      declared: true,
      lead_set: incident.lead.present?,
      resolved: incident.closed? || incident.canceled?,
      written_up: incident.postmortem.present? && !incident.postmortem.generating?,
      write_up_dropped: incident.canceled?
    )
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
