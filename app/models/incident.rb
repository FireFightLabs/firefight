class Incident < ApplicationRecord
  VISIBILITY_PUBLIC = "public"
  VISIBILITY_PRIVATE = "private"

  include Incident::Sequencing
  include Incident::Snapshots
  include Incident::RoleManagement
  include Incident::Lifecycle
  include Incident::Metrics
  include Incident::ChannelNaming
  include Incident::Serialization

  belongs_to :workspace
  belongs_to :declared_by, class_name: "WorkspaceMembership"
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

  after_destroy_commit :clear_transcript_cache

  validates :sequence_number, presence: true, uniqueness: { scope: :workspace_id }
  validates :identifier, presence: true, uniqueness: { scope: :workspace_id }
  validates :declared_at, presence: true

  scope :in_channel, ->(channel_id) { where(channel_id: channel_id) }
  scope :active, -> { joins(:incident_status).merge(IncidentStatus.live) }
  scope :closed, -> { joins(:incident_status).merge(IncidentStatus.closed) }
  scope :canceled, -> { joins(:incident_status).merge(IncidentStatus.canceled) }
  scope :by_severity, -> { joins(:incident_severity).order("incident_severities.rank DESC") }
  scope :recent, -> { order(declared_at: :desc) }

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

  private

  def clear_transcript_cache
    IncidentTranscriptCache.clear!(self)
  end
end
