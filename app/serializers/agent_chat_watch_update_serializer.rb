# One line a watch said in this chat: a milestone, taking longer than usual, or how it ended, placed by when it was said.
class AgentChatWatchUpdateSerializer < BaseSerializer
  object_as :update

  type :string
  def id
    update.id
  end

  type :string
  def watch_id
    update.watch_id
  end

  type :string
  def title
    update.watch.title
  end

  type Chat::Watch::Update::KINDS.map(&:inspect).join(" | ")
  def kind
    update.kind
  end

  # How it went, for the mark beside the line: a milestone, slow, done, failed, timed out or stopped.
  type Conversation::Watches::TONES.map(&:inspect).join(" | ")
  def tone
    Conversation::Watches.said(update.watch, update).tone
  end

  type :string
  def text
    update.text
  end

  type :string
  def at
    update.created_at.utc.iso8601(3)
  end
end
