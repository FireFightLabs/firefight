class AgentChatSerializer < BaseSerializer
  object_as :conversation

  attributes(id: { type: :string })

  # A chat asked in the platform shows the person's words as the platform does, from the platform_texts handed in.
  type :string
  def title
    question = conversation.title_question
    question ? platform_text(question).truncate(Conversation::TITLE_LIMIT) : conversation.display_title
  end

  type :string
  def preview
    question = conversation.preview_question
    question ? platform_text(question).truncate(Conversation::PREVIEW_LIMIT) : conversation.preview
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

  # Stop was pressed on the answer under way, kept on the chat's row, so a reload still says Halon is stopping. Read for
  # an opened chat only, since a list has no Stop.
  type :boolean
  def stopRequested
    options.fetch(:opened, false) && conversation.answer_owed? && conversation.chat&.cancelled == true
  end

  # When the answer under way began, so the time the page shows counts from there however often it is reloaded.
  type "string | null"
  def workingSince
    conversation.answer_owed_since&.utc&.iso8601(3) if conversation.answer_owed?
  end

  def platform_text(text) = options.fetch(:platform_texts, {}).fetch(text, text)
end
