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
  def self.for_reply(message, reads: nil) = for_replies([ message ], reads: reads).fetch(message.id)

  # The same for several replies of one chat, by reply id, read with a fixed number of queries however many there are, so
  # a page of replies costs what one does.
  def self.for_replies(replies, reads: nil)
    return {} if replies.empty?

    chat = replies.first.chat
    first, last = replies.minmax_by(&:created_at)
    questions = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false)
    since = questions.where(created_at: ..first.created_at).maximum(:created_at) || Time.at(0)
    started = first == last ? [ since ] : questions.where(created_at: since..last.created_at).pluck(:created_at).sort
    asked = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT).where(created_at: since..last.created_at).pluck(:id, :created_at)
    calls = answered_calls(asked.map(&:first))
    beside = beside_reads(chat, calls)
    reads ||= ->(name, arguments) { Chat::Tools::LookFirst.read?(chat.workspace, name, arguments) }
    replies.to_h do |reply|
      turn = started.reverse.find { |at| at <= reply.created_at } || Time.at(0)
      in_turn = asked.filter_map { |id, at| id if at.between?(turn, reply.created_at) }.to_set
      [ reply.id, of_calls(chat, calls.select { |call| in_turn.include?(call.message_id) }, reads: reads, beside: beside) ]
    end
  end

  # beside is what the helpers and specialists started in the chat read, from beside_reads, of which only those a call
  # here started count.
  def self.of_calls(chat, calls, reads:, beside:)
    keys = calls.map(&:tool_call_id).to_set
    read_beside = beside.flat_map { |key, read| keys.include?(key) ? read : [] }
    (calls + read_beside).reject { |call| STARTS_OTHERS.include?(call.name) || OWN.include?(call.name) || Chat::Tools.internal_names.include?(call.name) }
                    .select { |call| reads.call(call.name, call.arguments.to_h.stringify_keys) }
                    .map { |call| source(chat.workspace, call) }
                    .uniq { |source| source.url || source.title }
  end

  # What each helper or specialist the calls started read, as its starting call's id and its calls, in the order they
  # were started.
  def self.beside_reads(chat, calls)
    starting = calls.select { |call| STARTS_OTHERS.include?(call.name) }.map(&:tool_call_id)
    return [] if starting.empty?

    helpers = Chat::Helper.where(chat: chat, tool_call_id: starting).in_order.includes(:own_chat).select(&:own_chat)
    chat_of = Chat::Message.where(chat_id: helpers.map { |helper| helper.own_chat.id }, role: Chat::Message::ROLE_ASSISTANT).pluck(:id, :chat_id).to_h
    read = answered_calls(chat_of.keys).group_by { |call| chat_of[call.message_id] }
    helpers.map { |helper| [ helper.tool_call_id, read.fetch(helper.own_chat.id, []) ] }
  end

  def self.answered_calls(message_ids)
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: message_ids)
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
  private_class_method :of_calls, :answered_calls, :beside_reads, :source
end
