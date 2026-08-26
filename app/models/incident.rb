class Incident < ApplicationRecord
  # Raised when an incident that is over is asked to do something only a live
  # incident can do. Carries the sentence the surface shows, so a dispatcher
  # can render it without knowing which rule refused.
  class NotActive < StandardError; end

  VISIBILITY_PUBLIC = "public"
  VISIBILITY_PRIVATE = "private"

  SOURCE_SLACK = "slack"
  SOURCE_ALERT = "alert"
  SOURCE_DASHBOARD = "dashboard"

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  include Incident::Sequencing
  include Incident::CustomFields
  include Incident::Snapshots
  include Incident::RoleManagement
  include Incident::Lifecycle
  include Incident::Metrics
  include Incident::ChannelNaming
  include Incident::Serialization

  belongs_to :workspace
  belongs_to :declared_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :source_api_key, class_name: "ApiKey", optional: true
  belongs_to :incident_status
  belongs_to :incident_severity
  belongs_to :incident_type, optional: true

  has_many :incident_events, dependent: :destroy
  has_many :incident_updates, dependent: :destroy
  has_many :incident_actions, dependent: :destroy
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incident_roles, through: :incident_role_assignments
  has_many :assigned_members, through: :incident_role_assignments, source: :workspace_membership
  has_many :shoutouts, dependent: :destroy
  has_one :postmortem, dependent: :destroy
  has_many :incident_relationships, dependent: :destroy
  has_many :inverse_incident_relationships, class_name: "IncidentRelationship",
           foreign_key: :related_incident_id, dependent: :destroy, inverse_of: :related_incident
  has_many :incident_transcript_messages, dependent: :destroy
  has_one :incident_summary, dependent: :destroy
  has_many :alerts, dependent: :nullify
  has_many :alert_groups, dependent: :destroy
  has_many :incident_runbooks, dependent: :destroy

  validates :sequence_number, presence: true, uniqueness: { scope: :workspace_id }
  validates :identifier, presence: true, uniqueness: { scope: :workspace_id }
  validates :declared_at, presence: true
  validates :source, presence: true

  scope :in_channel, ->(channel_id) { where(channel_id: channel_id) }
  scope :active, -> { joins(:incident_status).merge(IncidentStatus.live) }
  scope :closed, -> { joins(:incident_status).merge(IncidentStatus.closed) }
  scope :canceled, -> { joins(:incident_status).merge(IncidentStatus.canceled) }
  scope :terminal, -> { joins(:incident_status).merge(IncidentStatus.terminal) }
  scope :by_severity, -> { joins(:incident_severity).order("incident_severities.rank DESC") }
  scope :recent, -> { order(declared_at: :desc) }
  scope :search, ->(query) {
    where("incidents.name ILIKE :q OR incidents.identifier ILIKE :q",
      q: "%#{sanitize_sql_like(query)}%")
  }
  scope :by_severity_slugs, ->(slugs) {
    where(incident_severity_id: IncidentSeverity.where(slug: slugs).select(:id))
  }
  scope :by_lifecycle_stage_keys, ->(keys) {
    where(incident_status_id: IncidentStatus.in_stage(keys).select(:id))
  }
  scope :with_list_associations, -> {
    includes(
      { incident_status: :incident_lifecycle_stage },
      :incident_severity,
      { declared_by: :user },
      incident_role_assignments: [ :incident_role, { workspace_membership: :user } ]
    )
  }
  scope :with_detail_associations, -> {
    includes(
      { incident_status: :incident_lifecycle_stage },
      :incident_severity,
      :incident_type,
      { declared_by: :user },
      :postmortem,
      incident_role_assignments: [ :incident_role, { workspace_membership: :user } ],
      incident_runbooks: { runbook: :runbook_steps }
    )
  }

  def self.filtered_list(filters: {}, page: nil, per_page: nil)
    scope = all.where(deleted_at: nil).with_list_associations.recent
    scope = scope.search(filters[:search]) if filters[:search].present?
    scope = scope.by_severity_slugs(filters[:severities]) if filters[:severities]&.any?
    scope = scope.by_lifecycle_stage_keys(filters[:lifecycle_stages]) if filters[:lifecycle_stages]&.any?

    total_count = scope.count
    per_page = (per_page || DEFAULT_PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
    total_pages = [ (total_count.to_f / per_page).ceil, 1 ].max
    page = (page || 1).to_i.clamp(1, total_pages)

    {
      incidents: scope.offset((page - 1) * per_page).limit(per_page),
      pagination: { page:, perPage: per_page, totalCount: total_count, totalPages: total_pages }
    }
  end

  def active?
    incident_status.live?
  end

  def closed?
    incident_status.closed?
  end

  def canceled?
    incident_status.canceled?
  end

  # Over, however it ended. Resolved and canceled differ in what they mean, but
  # not in whether anyone is still working the incident.
  def terminal?
    closed? || canceled?
  end

  def escalation_blocked_reason
    terminal_blocked_reason("it can no longer be escalated")
  end

  # The one rule the status machine refuses: an incident that is over cannot
  # swap between closed and canceled. Reopen it, then close or cancel.
  def status_change_blocked_reason(new_status)
    return nil unless terminal?
    return nil if incident_status.incident_lifecycle_stage_id == new_status.incident_lifecycle_stage_id
    return nil if new_status.live?

    terminal_blocked_reason("it cannot be #{new_status.canceled? ? "canceled" : "closed"} without being reopened first")
  end

  def lead_assignment_blocked_reason
    terminal_blocked_reason("it can no longer be assigned a lead")
  end

  # Why a responder surface can no longer change this incident, or nil. The
  # lead and role guards each state this rule in their own words, for the same
  # reason. Every change announces itself in a channel that may already be
  # archived. Surfaces ask for the sentence rather than deciding what terminal
  # means for themselves.
  def change_blocked_reason
    terminal_blocked_reason("it can no longer be changed")
  end

  # Named after the role rather than the verb. A workspace renames these, and
  # the same sentence has to cover clearing a role as well as filling one.
  def role_assignment_blocked_reason(role)
    return lead_assignment_blocked_reason if role.slug == IncidentRole::SLUG_INCIDENT_LEAD

    terminal_blocked_reason("its #{role.name} can no longer be changed")
  end

  # The timeline, with each update snapshot linked to the one before it from
  # a single ordered load. "Before" is defined by the same order the
  # timeline renders, never by a per-row timestamp query.
  def timeline_events
    events = incident_events.chronological.with_attached_artifact.includes(:actor, eventable: nil).to_a
    updates = events.map(&:eventable).grep(IncidentUpdate)
    ActiveRecord::Associations::Preloader.new(
      records: updates, associations: [ :incident_status, :incident_severity, :incident_type, { lead: :user }, { declared_by: :user } ]
    ).call
    updates.each_cons(2) { |earlier, later| later.previous_update = earlier }
    ActiveRecord::Associations::Preloader.new(
      records: events.map(&:eventable).grep(IncidentActionUpdate), associations: [ { assignee: :user } ]
    ).call
    references = IncidentEvent::References.for(self, events)
    events.each { |event| event.references = references }
    events
  end

  # Every attached runbook renders the state of its own steps, so they share
  # one load rather than querying per attachment.
  def runbook_step_actions
    @runbook_step_actions ||= incident_actions.active
      .where.not(runbook_step_id: nil)
      .includes(assignee: :user)
      .index_by(&:runbook_step_id)
  end

  def attachable_runbooks
    workspace.runbooks.active.ordered.where.not(id: incident_runbooks.select(:runbook_id))
  end

  def related_incidents
    ids = IncidentRelationship.related
      .where(incident_id: id)
      .or(IncidentRelationship.related.where(related_incident_id: id))
      .pluck(:incident_id, :related_incident_id)
      .flatten.uniq - [ id ]
    workspace.incidents.where(id: ids)
  end

  def duplicate_of
    rel = incident_relationships.duplicates.first
    rel&.related_incident
  end

  def duplicates
    inverse_incident_relationships.duplicates.map(&:incident)
  end

  private

  # One sentence saying why a responder action cannot run on an incident that
  # is over, or nil when it can. Every entry point renders this rather than
  # deciding the rule again.
  def terminal_blocked_reason(clause)
    return nil unless terminal?

    "#{identifier} is #{canceled? ? "canceled" : "closed"}, so #{clause}."
  end
end
