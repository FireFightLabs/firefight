# What Halon read to give an answer, as a list under it, the way a terminal agent shows its tool calls: each read of its
# turn that answered, titled as its step and with the page it came from when its result gave one. It is built from the
# turn's own tool calls and results, a specialist's and a helper's reads included, never from links the model wrote, so
# it says what was read rather than what was claimed.
module Chat::Sources
  Source = Data.define(:title, :url) do
    def to_h = { title: title, url: url }
  end

  # Past this the list says how many more it read.
  SHOWN = 12
  URL = %r{https://[^\s"'<>)\]\\`]+}
  TRAILING = /[.,;:]+\z/
  # Calls that start other reads rather than read anything themselves. What those read is listed instead.
  STARTS_OTHERS = [ Chat::Helper::ASK_SPECIALIST, Chat::Tools::Helpers::NAME ].freeze
  # Halon's own bookkeeping, which read nothing.
  OWN = [ Chat::Tools::Theories::NAME ].freeze

  # The reads of the turn a reply ended, from the person's message before it to the reply. reads says whether a call
  # read, given its name and arguments, so a replay can judge it by its scenario.
  def self.for_reply(message, reads: nil)
    chat = message.chat
    started = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).where(created_at: ..message.created_at).maximum(:created_at)
    asked = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT).where(created_at: (started || Time.at(0))..message.created_at)
    reads ||= ->(name, arguments) { Chat::Tools::LookFirst.read?(chat.workspace, name, arguments) }
    of_calls(chat, answered_calls(asked), reads: reads)
  end

  def self.of_calls(chat, calls, reads:)
    own_chats = Chat::Helper.where(chat: chat, tool_call_id: calls.select { |call| STARTS_OTHERS.include?(call.name) }.map(&:tool_call_id))
                            .in_order.includes(:own_chat).filter_map(&:own_chat)
    beside = own_chats.flat_map { |own| answered_calls(own.messages.where(role: Chat::Message::ROLE_ASSISTANT)) }
    (calls + beside).reject { |call| STARTS_OTHERS.include?(call.name) || OWN.include?(call.name) || Chat::Tools.internal_names.include?(call.name) }
                    .select { |call| reads.call(call.name, call.arguments.to_h.stringify_keys) }
                    .map { |call| source(chat.workspace, call) }
                    .uniq { |source| source.url || source.title }
  end

  def self.answered_calls(messages)
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: messages.select(:id))
                                   .where.not(result_id: nil).where(failed: false).includes(:result).order(:created_at, :id).to_a
  end

  def self.source(workspace, call)
    title = Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name.to_s.humanize
    Source.new(title: title, url: link_in(call.result&.content))
  end

  # The page a result came from: the link line a pack adds, else the first https address it holds, with credentials taken
  # out like every answer.
  def self.link_in(content)
    text = Chat::SecretFree.redacted(FirefightAi::Evidence.unframe(content).body)
    cited = Integrations::SourceLinks.cited_in(text)
    (cited&.url || text[URL])&.sub(TRAILING, "")
  end

  # Shown under an answer: the first SHOWN and how many more.
  def self.shown(sources) = [ sources.first(SHOWN), [ sources.size - SHOWN, 0 ].max ]
  private_class_method :answered_calls, :source
end
