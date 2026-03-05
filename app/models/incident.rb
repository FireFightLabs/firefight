class Incident < ApplicationRecord
  include Incident::Sequencing
  include Incident::Snapshots
  include Incident::RoleManagement
  include Incident::Lifecycle
  include Incident::Metrics
  include Incident::ChannelNaming

  belongs_to :workspace
  belongs_to :declared_by, class_name: "WorkspaceMembership"
  belongs_to :incident_status
  belongs_to :incident_severity

  has_many :incident_events, dependent: :destroy
  has_many :incident_updates, dependent: :destroy
  has_many :incident_actions, dependent: :destroy
  has_many :incident_role_assignments, dependent: :destroy
  has_many :incident_roles, through: :incident_role_assignments
  has_many :assigned_members, through: :incident_role_assignments, source: :workspace_membership

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
end
