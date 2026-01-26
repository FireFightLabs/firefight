class IncidentRoleAssignment < ApplicationRecord
  belongs_to :incident
  belongs_to :incident_role
  belongs_to :workspace_membership
  belongs_to :assigned_by, class_name: "WorkspaceMembership", optional: true

  validates :incident_role_id, uniqueness: { scope: :incident_id }

  before_validation :set_assigned_at, on: :create

  scope :recent, -> { order(assigned_at: :desc) }

  private

  def set_assigned_at
    self.assigned_at ||= Time.current
  end
end
