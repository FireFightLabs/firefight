# What Halon is told when a person replies in their direct messages to a message it sent them on its own, such as a watch
# update or a held call: the message's words and what it belongs to as it stands now, so the answer can act on it. What
# it reads came partly from connected systems, so it is framed as evidence.
class Conversation::RepliedTo
  FRAME = "replied_to".freeze
  INTRO = "The person is replying in your direct messages to this message you sent them. Answer about it, and act on what " \
          "it belongs to if they ask.".freeze
  # The records Halon posts to someone's direct messages and keeps the message of.
  SOURCES = [ Chat::Watch::Update, Chat::HeldCall, Chat::Plan, Chat::OwnerAsk, Chat::Mitigation, CodeAgentSession::Notice ].freeze
  RESULT_LIMIT = 500

  def self.context(workspace, channel_id:, message_id:, text:)
    record = find(workspace, channel_id, message_id)
    shown = { message: text.presence, belongs_to: (describe(record) if record) }.compact
    return nil if shown.empty?

    "#{INTRO}\n#{FirefightAi::Evidence.frame(FRAME, JSON.pretty_generate(shown))}"
  end

  def self.find(workspace, channel_id, message_id)
    SOURCES.each do |source|
      record = source.find_by(message_channel_id: channel_id, message_id: message_id)
      return record if record && workspace_of(record) == workspace.id
    end
    nil
  end
  private_class_method :find

  def self.workspace_of(record)
    case record
    when Chat::Watch::Update then record.watch.workspace_id
    when Chat::HeldCall then record.chat.workspace_id
    else record.workspace_id
    end
  end
  private_class_method :workspace_of

  def self.describe(record)
    case record
    when Chat::Watch::Update then { watch: Chat::Watch::Shown.summary(record.watch) }
    when Chat::HeldCall
      { held_call: { tool: record.tool_name, target: record.target, status: record.shown_status, result: record.result.to_s.truncate(RESULT_LIMIT).presence }.compact }
    when Chat::Plan
      { plan: { goal: record.goal, status: record.status, standing: record.standing.presence, run_at: record.run_at&.utc&.iso8601,
                stop_reason: record.stop_reason }.compact }
    when Chat::OwnerAsk then { owner_ask: { asked: record.headline, owner: record.owner_name, status: record.status } }
    when Chat::Mitigation
      { change_customers_feel: { title: record.title, status: record.status, expires_at: record.expires_at&.utc&.iso8601 }.compact }
    when CodeAgentSession::Notice then { pull_request: { headline: record.headline, status: record.status } }
    end
  end
  private_class_method :describe
end
