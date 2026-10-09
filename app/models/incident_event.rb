class IncidentEvent < ApplicationRecord
  # Dismissal is error correction on an AI note, never a way to hide what a person did.
  class NotDismissable < StandardError; end

  INCIDENT_CREATED = "incident.created"
  INCIDENT_UPDATED = "incident.updated"
  LEAD_ASSIGNED = "lead.assigned"
  ROLE_ASSIGNED = "role.assigned"
  ROLE_UNASSIGNED = "role.unassigned"
  ACTION_CREATED = "action.created"
  ACTION_PICKED_UP = "action.picked_up"
  ACTION_COMPLETED = "action.completed"
  ACTION_REASSIGNED = "action.reassigned"
  # Changes to an item from its linked issue or from an agent over MCP.
  ACTION_RENAMED = "action.renamed"
  ACTION_REOPENED = "action.reopened"
  ACTION_UNASSIGNED = "action.unassigned"
  INCIDENT_ESCALATED = "incident.escalated"
  INCIDENT_RESOLVED = "incident.resolved"
  INCIDENT_REOPENED = "incident.reopened"
  INCIDENT_CANCELED = "incident.canceled"
  POSTMORTEM_GENERATED = "postmortem.generated"
  # A person started from an empty document, with no AI draft.
  POSTMORTEM_STARTED = "postmortem.started"
  POSTMORTEM_EDITED = "postmortem.edited"
  RELATIONSHIP_CREATED = "relationship.created"
  MARKED_DUPLICATE = "incident.marked_duplicate"
  MERGED_INTO = "incident.merged_into"
  MESSAGE_PINNED = "message.pinned"
  MESSAGE_UNPINNED = "message.unpinned"
  MESSAGE_FILE_SHARED = "message.file_shared"
  INCIDENT_ACCEPTED = "incident.accepted"
  ESCALATION_ACKNOWLEDGED = "incident.escalation_acknowledged"
  ESCALATION_NUDGED = "incident.escalation_nudged"
  ALERT_ATTACHED = "alert.attached"
  ALERT_RESOLVED = "alert.resolved"
  RUNBOOK_ATTACHED = "runbook.attached"
  RUNBOOK_APPLIED = "runbook.applied"
  MILESTONE_NOTED = "milestone.noted"
  INVESTIGATION_STARTED = "investigation.started"
  INVESTIGATION_ANSWERED = "investigation.answered"
  INVESTIGATION_STOPPED = "investigation.stopped"
  INVESTIGATION_EVENTS = [ INVESTIGATION_STARTED, INVESTIGATION_ANSWERED, INVESTIGATION_STOPPED ].freeze
  # The events whose snapshot carries what the responder posted, written as markdown.
  UPDATE_MESSAGE_EVENTS = [ INCIDENT_UPDATED, INCIDENT_CANCELED ].freeze

  # The extractor picks one per note and the timeline colours the entry from it.
  MILESTONE_HYPOTHESIS = "hypothesis"
  MILESTONE_FINDING = "finding"
  MILESTONE_ROOT_CAUSE = "root_cause"
  MILESTONE_MITIGATION = "mitigation"
  MILESTONE_DECISION = "decision"
  MILESTONE_BLOCKER = "blocker"
  MILESTONE_IMPACT = "impact"
  MILESTONE_RECOVERY = "recovery"

  MILESTONE_KINDS = [
    MILESTONE_HYPOTHESIS, MILESTONE_FINDING, MILESTONE_ROOT_CAUSE, MILESTONE_MITIGATION,
    MILESTONE_DECISION, MILESTONE_BLOCKER, MILESTONE_IMPACT, MILESTONE_RECOVERY
  ].freeze

  EVENT_TYPES = [
    INCIDENT_CREATED, INCIDENT_UPDATED, INCIDENT_ACCEPTED, LEAD_ASSIGNED,
    ROLE_ASSIGNED, ROLE_UNASSIGNED,
    ACTION_CREATED, ACTION_PICKED_UP, ACTION_COMPLETED, ACTION_REASSIGNED, ACTION_RENAMED, ACTION_REOPENED, ACTION_UNASSIGNED,
    INCIDENT_ESCALATED, INCIDENT_RESOLVED, INCIDENT_REOPENED, INCIDENT_CANCELED, POSTMORTEM_GENERATED, POSTMORTEM_STARTED, POSTMORTEM_EDITED,
    RELATIONSHIP_CREATED, MARKED_DUPLICATE, MERGED_INTO,
    MESSAGE_PINNED, MESSAGE_UNPINNED, MESSAGE_FILE_SHARED,
    ESCALATION_ACKNOWLEDGED, ESCALATION_NUDGED,
    ALERT_ATTACHED, ALERT_RESOLVED,
    RUNBOOK_ATTACHED, RUNBOOK_APPLIED,
    MILESTONE_NOTED,
    *INVESTIGATION_EVENTS
  ].freeze

  EVENT_DESCRIPTIONS = {
    INCIDENT_CREATED => "created the incident",
    INCIDENT_UPDATED => "updated the incident",
    LEAD_ASSIGNED => "assigned the lead to",
    ROLE_ASSIGNED => "assigned an incident role",
    ROLE_UNASSIGNED => "cleared an incident role",
    ACTION_CREATED => "created an action item",
    ACTION_PICKED_UP => "picked up an action item",
    ACTION_COMPLETED => "completed an action item",
    ACTION_REASSIGNED => "reassigned an action item",
    ACTION_RENAMED => "renamed an action item",
    ACTION_REOPENED => "reopened an action item",
    ACTION_UNASSIGNED => "unassigned an action item",
    INCIDENT_ACCEPTED => "accepted the incident from triage",
    INCIDENT_ESCALATED => "escalated the incident to",
    INCIDENT_RESOLVED => "resolved the incident",
    INCIDENT_REOPENED => "reopened the incident",
    INCIDENT_CANCELED => "canceled the incident",
    POSTMORTEM_GENERATED => "generated the postmortem",
    POSTMORTEM_STARTED => "started the postmortem",
    POSTMORTEM_EDITED => "edited the postmortem",
    RELATIONSHIP_CREATED => "linked",
    MARKED_DUPLICATE => "marked the incident as a duplicate of",
    MERGED_INTO => "merged the incident into",
    MESSAGE_PINNED => "pinned a message",
    MESSAGE_UNPINNED => "unpinned a message",
    MESSAGE_FILE_SHARED => "shared a file",
    ESCALATION_ACKNOWLEDGED => "acknowledged the escalation",
    ESCALATION_NUDGED => "sent an escalation reminder to",
    ALERT_ATTACHED => "attached the alert",
    ALERT_RESOLVED => "resolved the alert",
    RUNBOOK_ATTACHED => "attached the runbook",
    RUNBOOK_APPLIED => "added runbook steps as actions",
    MILESTONE_NOTED => "noted",
    INVESTIGATION_STARTED => "started",
    INVESTIGATION_ANSWERED => "found",
    INVESTIGATION_STOPPED => "stopped"
  }.freeze

  # Only events backed by a Recordable snapshot. Action-only events carry
  # their payload in metadata and have no eventable.
  UPDATE_TYPE_MAP = {
    INCIDENT_CREATED     => IncidentUpdate::CREATED,
    INCIDENT_UPDATED     => IncidentUpdate::UPDATED,
    INCIDENT_ACCEPTED    => IncidentUpdate::ACCEPTED,
    LEAD_ASSIGNED        => IncidentUpdate::LEAD_ASSIGNED,
    INCIDENT_RESOLVED    => IncidentUpdate::CLOSED,
    INCIDENT_REOPENED    => IncidentUpdate::REOPENED,
    INCIDENT_CANCELED    => IncidentUpdate::CANCELED,
    MERGED_INTO          => IncidentUpdate::CANCELED,
    ACTION_CREATED       => IncidentActionUpdate::CREATED,
    ACTION_PICKED_UP     => IncidentActionUpdate::PICKED_UP,
    ACTION_COMPLETED     => IncidentActionUpdate::COMPLETED,
    ACTION_REASSIGNED    => IncidentActionUpdate::REASSIGNED,
    ACTION_RENAMED       => IncidentActionUpdate::RENAMED,
    ACTION_REOPENED      => IncidentActionUpdate::REOPENED,
    ACTION_UNASSIGNED    => IncidentActionUpdate::UNASSIGNED,
    POSTMORTEM_GENERATED => PostmortemUpdate::GENERATED,
    POSTMORTEM_STARTED   => PostmortemUpdate::STARTED,
    POSTMORTEM_EDITED    => PostmortemUpdate::EDITED
  }.freeze

  def self.update_type_for(event_type)
    UPDATE_TYPE_MAP.fetch(event_type) do
      raise ArgumentError, "no recordable update_type for event_type=#{event_type.inspect}"
    end
  end

  # What the timeline calls an event nobody performed.
  AUTOMATED_ACTOR_NAME = "Firefight"

  belongs_to :incident
  belongs_to :actor, polymorphic: true, optional: true
  attr_accessor :references
  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate PostmortemUpdate], optional: true
  has_one_attached :artifact
  # Active Storage purges the blob in an after-commit hook that needs the
  # owner row, gone by then. Prepended to run before the attachment's own destroy.
  before_destroy :purge_artifact, prepend: true
  has_many :webhook_deliveries, dependent: :delete_all

  # The file is served only when the attachment names this event and holds the blob this event
  # recorded archiving, so a row pointing at the wrong owner never reaches anyone.
  def archived_file
    attachment = artifact.attachment
    return nil unless attachment
    return nil unless attachment.record_id == id && attachment.blob_id.to_s == metadata.to_h["blob_id"].to_s

    attachment
  end

  def milestone?
    event_type == MILESTONE_NOTED
  end

  def dismissed?
    metadata.to_h["dismissed_at"].present?
  end

  # The row stays and the dashboard files it under dismissed notes. Any
  # principal may dismiss, so the name is stored and the member id only for a person.
  def dismiss!(by:)
    raise NotDismissable, "Only AI-noted milestones can be dismissed." unless milestone?

    update!(metadata: metadata.to_h.merge({
      "dismissed_at" => Time.current.iso8601,
      "dismissed_by_member_id" => by.is_a?(WorkspaceMembership) ? by.id : nil,
      "dismissed_by_name" => by&.actor_display_name
    }.compact))
  end

  def escalation_acknowledged?
    metadata&.dig("acknowledged_by_platform_user_id").present?
  end

  after_create_commit :publish_to_event_bus

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validate :eventable_matches_event_type

  scope :chronological, -> { order(created_at: :asc) }
  # A dismissed note stays on the row for the dashboard, every other surface skips it.
  scope :undismissed, -> { where("metadata->>'dismissed_at' IS NULL") }
  scope :recent, -> { order(created_at: :desc) }
  scope :updates, -> { where(eventable_type: "IncidentUpdate") }
  scope :action_updates, -> { where(eventable_type: "IncidentActionUpdate") }
  scope :postmortem_updates, -> { where(eventable_type: "PostmortemUpdate") }

  def changed_fields
    eventable&.changed_fields || []
  end

  def changed?(field = nil)
    return super() if field.nil?

    changed_fields.include?(field.to_s)
  end

  def automated?
    actor.nil?
  end

  def actor_name
    actor&.actor_display_name || AUTOMATED_ACTOR_NAME
  end

  # For text surfaces. The dashboard renders stem and subject separately so
  # the subject can be a link or a person.
  def description
    [ description_stem, subject_label ].compact.join(" ")
  end

  # Role events name the role, they carry no snapshot to render a before and after from.
  def description_stem
    role_name = metadata.to_h["role_name"]
    return EVENT_DESCRIPTIONS[event_type] if role_name.blank?

    case event_type
    when ROLE_ASSIGNED then "assigned the #{role_name} role to"
    when ROLE_UNASSIGNED then "cleared the #{role_name} role"
    else EVENT_DESCRIPTIONS[event_type]
    end
  end

  # Read from what the writer stored, so no surface has to resolve an id.
  def subject_label
    meta = metadata.to_h
    case event_type
    when RUNBOOK_ATTACHED then meta["runbook_name"]
    when ALERT_ATTACHED, ALERT_RESOLVED then meta["title"]
    when RELATIONSHIP_CREATED, MARKED_DUPLICATE then meta["related_identifier"]
    when MERGED_INTO then meta["canonical_identifier"]
    when INCIDENT_ESCALATED, ESCALATION_NUDGED then meta["escalated_to_name"]
    when ROLE_ASSIGNED then meta["member_name"]
    when LEAD_ASSIGNED then eventable&.lead&.actor_display_name
    when MILESTONE_NOTED then meta["statement"]
    when INVESTIGATION_STARTED then "an investigation"
    when INVESTIGATION_ANSWERED then "an answer"
    when INVESTIGATION_STOPPED then "the investigation"
    end
  end

  # What the responder posted with the update, as markdown.
  def update_message
    return nil unless UPDATE_MESSAGE_EVENTS.include?(event_type)

    eventable.try(:message).presence
  end

  # What the update changed, before and after. The before needs the previous snapshot,
  # which Incident#timeline_events or with_update_history links.
  def update_changes
    update = eventable
    return [] unless UPDATE_MESSAGE_EVENTS.include?(event_type) && update.is_a?(IncidentUpdate) && update.changed_fields.any?

    update.changes_since(update.previous_update, field_definitions: references&.field_definitions || {})
  end

  # Links each update to the one before it from the incident's whole history, so a page
  # of events still knows what a change replaced. One query per call, never per row.
  def self.with_update_history(events)
    updates = events.select { |event| UPDATE_MESSAGE_EVENTS.include?(event.event_type) }
      .map(&:eventable).grep(IncidentUpdate).select { |update| update.changed_fields.any? }
    return events if updates.empty?

    history = IncidentUpdate.where(incident_id: updates.map(&:incident_id).uniq).order(:created_at).to_a
    previous = history.group_by(&:incident_id).values.flat_map { |rows| rows.each_cons(2).map { |earlier, later| [ later.id, earlier ] } }.to_h
    updates.each { |update| update.previous_update = previous[update.id] }
    ActiveRecord::Associations::Preloader.new(
      records: updates + updates.filter_map(&:previous_update),
      associations: [ :incident_status, :incident_severity, :incident_type, :declared_by, { lead: :user } ]
    ).call

    definitions = References.field_definitions_for(updates.first.workspace, events)
    events.each do |event|
      event.references ||= References.new(members: {}, runbooks: {}, incidents: {}, field_definitions: definitions)
    end
    events
  end

  # A milestone says what it needs to inside its sentence, kind and said_by
  # as their own keys would ship data nothing reads.
  def to_context_hash
    {
      type: event_type, at: created_at.iso8601, by: actor_name, description: description,
      message: update_message,
      changes: update_changes.map { |change| { label: change.label, before: change.before, after: change.after } }.presence
    }.compact
  end

  private

  def eventable_matches_event_type
    return if event_type.blank?

    snapshot_backed = UPDATE_TYPE_MAP.key?(event_type)

    if snapshot_backed && eventable.nil?
      errors.add(:eventable, "is required for event_type=#{event_type}")
    elsif !snapshot_backed && eventable.present?
      errors.add(:eventable, "must be nil for event_type=#{event_type}")
    end
  end

  def publish_to_event_bus
    ProcessDomainEventJob.perform_later(
      "event_id" => id,
      "event_type" => event_type,
      "incident_id" => incident_id,
      "actor_type" => actor_type,
      "actor_id" => actor_id,
      "data" => metadata,
      "occurred_at" => created_at.iso8601(6)
    )
  end

  def purge_artifact
    return unless artifact.attached?

    blob = artifact.blob
    artifact.detach
    blob.purge_later
  end
end
