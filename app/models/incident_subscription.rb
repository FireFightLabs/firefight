# Every reply Firefight posts in the announcement thread reaches the
# subscriber as a direct message.
class IncidentSubscription < ApplicationRecord
  include Incident::LiveSignal

  shown_on_incident_page Incident::LiveSignal::PART_INCIDENT

  belongs_to :workspace
  belongs_to :incident
  belongs_to :workspace_membership

  validates :workspace_membership_id, uniqueness: { scope: :incident_id }
end
