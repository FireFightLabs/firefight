class IncidentEvent < ApplicationRecord
  # Raised when something that is not an AI-noted milestone is asked to be
  # dismissed. Dismissal is error correction on a note, never a way to hide
  # what a person did.
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
  INCIDENT_ESCALATED = "incident.escalated"
  INCIDENT_RESOLVED = "incident.resolved"
  INCIDENT_REOPENED = "incident.reopened"
  INCIDENT_CANCELED = "incident.canceled"
  POSTMORTEM_GENERATED = "postmortem.generated"
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

  # What a milestone note is about. The extractor picks one per note and the
  # timeline colours the entry from it.
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
    ACTION_CREATED, ACTION_PICKED_UP, ACTION_COMPLETED, ACTION_REASSIGNED,
    INCIDENT_ESCALATED, INCIDENT_RESOLVED, INCIDENT_REOPENED, INCIDENT_CANCELED, POSTMORTEM_GENERATED, POSTMORTEM_EDITED,
    RELATIONSHIP_CREATED, MARKED_DUPLICATE, MERGED_INTO,
    MESSAGE_PINNED, MESSAGE_UNPINNED, MESSAGE_FILE_SHARED,
    ESCALATION_ACKNOWLEDGED, ESCALATION_NUDGED,
    ALERT_ATTACHED, ALERT_RESOLVED,
    RUNBOOK_ATTACHED, RUNBOOK_APPLIED,
    MILESTONE_NOTED
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
    INCIDENT_ACCEPTED => "accepted the incident from triage",
    INCIDENT_ESCALATED => "escalated the incident to",
    INCIDENT_RESOLVED => "resolved the incident",
    INCIDENT_REOPENED => "reopened the incident",
    INCIDENT_CANCELED => "canceled the incident",
    POSTMORTEM_GENERATED => "generated the postmortem",
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
    MILESTONE_NOTED => "noted"
  }.freeze

  # Only events backed by a Recordable snapshot appear here. Action-only events
  # (pins, file shares, escalations, relationships) carry their payload in
  # `metadata` and have no eventable.
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
    POSTMORTEM_GENERATED => PostmortemUpdate::GENERATED,
    POSTMORTEM_EDITED    => PostmortemUpdate::EDITED
  }.freeze

  def self.update_type_for(event_type)
    UPDATE_TYPE_MAP.fetch(event_type) do
      raise ArgumentError, "no recordable update_type for event_type=#{event_type.inspect}"
    end
  end

  # What the timeline calls an event nobody performed: a rule, a workflow, or
  # the bot acting on the workspace's configuration.
  AUTOMATED_ACTOR_NAME = "Firefight"

  belongs_to :incident
  belongs_to :actor, polymorphic: true, optional: true
  attr_accessor :references
  delegated_type :eventable, types: %w[IncidentUpdate IncidentActionUpdate PostmortemUpdate], optional: true
  has_one_attached :artifact
  has_many :webhook_deliveries, dependent: :delete_all

  def milestone?
    event_type == MILESTONE_NOTED
  end

  def dismissed?
    metadata.to_h["dismissed_at"].present?
  end

  # Error correction, not deletion. The row stays, and the dashboard files it
  # under the day's dismissed notes. Any principal may dismiss, so the name is
  # always stored and the member id only when a person did it.
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
  # A dismissed note was a wrong reading. It stays on the row so the
  # correction is visible in the dashboard, and every other surface skips it.
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

  # The full sentence, for text surfaces (Slack, AI context, webhooks). The
  # dashboard renders the stem and the subject separately so the subject can
  # be a link or a person.
  def description
    [ description_stem, subject_label ].compact.join(" ")
  end

  # Role events name the role, since they carry no snapshot to render a
  # before/after from, and "assigned an incident role" on its own leaves out
  # the fact a reader wants.
  def description_stem
    role_name = metadata.to_h["role_name"]
    return EVENT_DESCRIPTIONS[event_type] if role_name.blank?

    case event_type
    when ROLE_ASSIGNED then "assigned the #{role_name} role to"
    when ROLE_UNASSIGNED then "cleared the #{role_name} role"
    else EVENT_DESCRIPTIONS[event_type]
    end
  end

  # The thing the sentence is about, read from what the writer stored, so no
  # surface has to resolve an id to say what happened.
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
    end
  end

  # Every consumer renders at, description and by, so a milestone says what it
  # needs to inside its sentence. Handing over kind and said_by as their own
  # keys would ship data nothing reads.
  def to_context_hash
    { type: event_type, at: created_at.iso8601, by: actor_name, description: description }
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
end
