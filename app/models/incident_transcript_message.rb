class IncidentTranscriptMessage < ApplicationRecord
  include Scrubbing

  DEFAULT_MESSAGES = 100
  MAX_MESSAGES = 500

  Page = Data.define(:messages, :more_before)

  belongs_to :workspace
  belongs_to :workspace_membership, optional: true
  belongs_to :incident

  validates :message_id, :platform_user_id, :posted_at, presence: true

  encrypts :content

  scope :kept, -> { where(deleted_at: nil) }

  # Matches the page sort exactly. Comparing posted_at alone would skip whatever
  # else was said in the same instant as the cursor.
  scope :before_cursor, ->(cursor) {
    where(
      "(incident_transcript_messages.posted_at, incident_transcript_messages.message_id) < (?, ?)",
      cursor.posted_at, cursor.message_id
    )
  }

  # A conversation reads newest last, but the part worth reading is the end, so
  # a page is taken backwards from the cursor and reversed. One row more than
  # asked for is read, which is how more_before knows whether to hand back a
  # cursor or say the start has been reached.
  def self.page(before: nil, limit: nil)
    size = (limit.presence || DEFAULT_MESSAGES).to_i.clamp(1, MAX_MESSAGES)
    scope = kept.order(posted_at: :desc, message_id: :desc).includes(:workspace_membership)
    scope = scope.before_cursor(find_by!(message_id: before.to_s)) if before.present?

    found = scope.limit(size + 1).to_a
    messages = found.first(size).reverse
    Page.new(messages: messages, more_before: found.size > size ? messages.first.message_id : nil)
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
