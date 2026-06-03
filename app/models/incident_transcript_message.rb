class IncidentTranscriptMessage < ApplicationRecord
  belongs_to :workspace
  belongs_to :workspace_membership, optional: true
  belongs_to :incident

  validates :slack_ts, :slack_user_id, :content, :posted_at, presence: true

  encrypts :content

  scope :kept, -> { where(deleted_at: nil) }
end
