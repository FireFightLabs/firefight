class IncidentTranscriptMessage < ApplicationRecord
  belongs_to :workspace
  belongs_to :workspace_membership, optional: true
  belongs_to :incident

  encrypts :content

  scope :kept, -> { where(deleted_at: nil) }
end
