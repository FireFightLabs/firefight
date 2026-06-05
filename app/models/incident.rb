class Incident < ApplicationRecord
  VISIBILITY_PUBLIC = "public"
  VISIBILITY_PRIVATE = "private"

  SOURCE_SLACK = "slack"

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  include Incident::Sequencing
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

  validates :sequence_number, presence: true, uniqueness: { scope: :workspace_id }
  validates :identifier, presence: true, uniqueness: { scope: :workspace_id }
  validates :declared_at, presence: true
  validates :source, presence: true

  scope :in_channel, ->(channel_id) { where(channel_id: channel_id) }
  scope :active, -> { joins(:incident_status).merge(IncidentStatus.live) }
  scope :closed, -> { joins(:incident_status).merge(IncidentStatus.closed) }
  scope :canceled, -> { joins(:incident_status).merge(IncidentStatus.canceled) }
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
    where(incident_status_id: IncidentStatus.joins(:incident_lifecycle_stage)
      .where(incident_lifecycle_stages: { key: keys }).select(:id))
  }
  scope :with_list_associations, -> {
    includes(
      { incident_status: :incident_lifecycle_stage },
      :incident_severity,
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
      incident_role_assignments: [ :incident_role, { workspace_membership: :user } ]
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

end
