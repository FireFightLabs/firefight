class AgentChatSerializer < BaseSerializer
  object_as :conversation

  attributes(id: { type: :string })

  type :string
  def title
    conversation.display_title
  end

  type :string
  def preview
    conversation.preview
  end

  type :boolean
  def pinned
    conversation.pinned?
  end

  # The list sorts itself on these, so changes land in place without a reload.
  type "string | null"
  def pinnedAt
    conversation.pinned_at&.utc&.iso8601(3)
  end

  type :string
  def lastActiveAt
    conversation.updated_at.utc.iso8601(3)
  end

  type :boolean
  def archived
    conversation.archived?
  end

  # Where a chat asked elsewhere lives, such as Slack for a direct message chat, and nil for a dashboard chat. The page
  # marks it in the list and points there rather than offering to ask.
  type "string | null"
  def askedIn
    conversation.asked_in
  end

  # A link that opens that place, sent only for the open chat.
  type "string | null"
  def askedInUrl
    options[:asked_in_url]
  end

  # An answer is owed, so the page shows the agent working and keeps the live stream over the saved copy.
  type :boolean
  def busy
    conversation.answer_owed?
  end
end
