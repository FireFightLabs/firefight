# One person following one incident from outside its channel. Every reply
# Firefight posts in the announcement thread reaches them as a direct message.
class IncidentSubscription < ApplicationRecord
  belongs_to :workspace
  belongs_to :incident
  belongs_to :workspace_membership

  validates :workspace_membership_id, uniqueness: { scope: :incident_id }
end
