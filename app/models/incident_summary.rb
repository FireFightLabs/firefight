class IncidentSummary < ApplicationRecord
  belongs_to :incident
  belongs_to :workspace
  belongs_to :inference, optional: true

  validates :content, :summary_up_to_ts, :generated_at, :model, presence: true

  encrypts :content
end
