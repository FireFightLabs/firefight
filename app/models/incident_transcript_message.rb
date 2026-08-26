class IncidentTranscriptMessage < ApplicationRecord
  include Scrubbing
  include Paging

  belongs_to :workspace
  belongs_to :workspace_membership, optional: true
  belongs_to :incident

  validates :message_id, :platform_user_id, :posted_at, presence: true

  encrypts :content

  scope :kept, -> { where(deleted_at: nil) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
