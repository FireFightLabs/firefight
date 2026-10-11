# One thread a direct message chat was asked in. The chat answers in the thread it was last asked in, and a reply in an
# earlier one still reaches it.
class Conversation::ThreadLink < ApplicationRecord
  self.table_name = "conversation_thread_links"

  belongs_to :workspace
  belongs_to :conversation

  validates :channel_id, :thread_id, presence: true
end
