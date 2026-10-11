# Look before you change. In a chat, a call that changes something in a connected system, or that resolves, cancels,
# deletes or revokes something in Firefight, names the reads that show it will help, in BECAUSE, and the call is checked
# against the reads Halon really made: in this turn, or in its previous answer while they are fresh, since a person
# approving what Halon just proposed needs no second look at the same thing. A change with none goes back to
# Halon before anyone is asked, and the confirmation shows the reads it named, so the person approves the reasoning and
# not only the call. Only a chat turn asks this. Investigations and watches only read, and a run nobody is in, such as a
# held call run once approved, keeps its own guards.
module Chat::Tools::LookFirst
  BECAUSE = "because".freeze
  # A read in Halon's previous answer still backs a change this long after it was made.
  PROPOSAL_FRESH_FOR = 10.minutes
  DESCRIPTION = "Each read that shows this change will help, by the name of the tool you called, then what it showed, such as " \
                "\"northflank_list_deployments: web has run 7676c83 since 14:02, when errors started\". Reads you made in this " \
                "turn count, and reads from your previous answer while they are under #{PROPOSAL_FRESH_FOR.in_minutes.to_i} minutes " \
                "old. Needed for any call that changes something".freeze
  SCHEMA = { "type" => "array", "items" => { "type" => "string" }, "description" => DESCRIPTION }.freeze
  BOUNCE = "Nothing you read in this turn shows this will help. Read first, then propose it.".freeze
  # A tool name, the first word of each entry.
  NAMED = /\A[A-Za-z0-9_.\-]+/

  # One read the change named, with what Halon said it showed.
  Support = Data.define(:label, :said)

  # Whether the run asks this at all: a chat turn that may change things.
  def self.applies?(agent_run) = agent_run.is_a?(Conversation::Turn) && !agent_run.reads_only? && agent_run.chat.present?

  def self.with_because(schema, required:)
    schema = schema.deep_dup
    schema["properties"] = (schema["properties"] || {}).merge(BECAUSE => SCHEMA)
    schema["required"] = (Array(schema["required"]) + [ BECAUSE ]).uniq if required
    schema
  end

  def self.named(given) = Array(given.to_h.stringify_keys[BECAUSE]).map { |entry| entry.to_s.strip }.reject(&:empty?)

  # Why the change goes back to Halon, or nil when a read from this turn backs it. A call already put to the person passed
  # this when it was asked, so it is never sent back after their answer.
  def self.refusal(agent_run, given, tool_call_id: nil)
    return unless applies?(agent_run)

    chat = agent_run.chat
    return if tool_call_id && chat.tool_calls.where(tool_call_id: tool_call_id).where.not(approval: nil).exists?

    entries = named(given)
    read = read_names(chat, agent_run.workspace)
    backed, unread = entries.partition { |entry| read.include?(tool_name(entry).downcase) }
    return if backed.any?

    missing = unread.map { |entry| tool_name(entry) }.uniq
    [ BOUNCE, ("You named #{missing.to_sentence}, which you did not read in this turn or recently enough." if missing.any?) ].compact.join(" ")
  end

  # The reads a change put to the person named, each as the step is titled and what Halon said it showed, from the turn
  # the call was made in.
  def self.support(chat, tool_call, workspace)
    message = tool_call.try(:message)
    entries = named(tool_call.arguments)
    return [] if chat.nil? || message.nil? || entries.empty?

    calls = reads(chat, workspace, until_at: message.created_at).group_by { |call| call.name.downcase }
    entries.filter_map do |entry|
      name = tool_name(entry)
      call = calls[name.downcase]&.last
      next unless call

      said = entry.delete_prefix(name).sub(/\A[\s:,.-]+/, "")
      Support.new(label: Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name, said: said)
    end
  end

  def self.read_names(chat, workspace) = reads(chat, workspace).map { |call| call.name.downcase }.to_set

  # The calls that read and answered in the turn running at until_at, which starts at the person's latest message, and
  # those of the answer before it made within PROPOSAL_FRESH_FOR of until_at. A specialist Halon asked in those reads for
  # it, so what it read counts as read there too.
  def self.reads(chat, workspace, until_at: nil)
    own = own_reads(chat, workspace, until_at: until_at)
    own + specialist_reads(chat, workspace, own)
  end

  def self.own_reads(chat, workspace, until_at: nil)
    person = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false)
    person = person.where(created_at: ..until_at) if until_at
    started, before = person.reorder(created_at: :desc).limit(2).pluck(:created_at)
    fresh_from = (until_at || Time.current) - PROPOSAL_FRESH_FOR
    messages = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT)
    messages = messages.where(created_at: (before || started)..) if started
    messages = messages.where(created_at: ..until_at) if until_at
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: messages.select(:id))
                                   .where.not(result_id: nil).where(failed: false).includes(:message).order(:created_at, :id)
                                   .select { |call| backs?(call, started, fresh_from) && read?(workspace, call.name, call.arguments) }
  end

  def self.specialist_reads(chat, workspace, calls)
    asked = calls.select { |call| call.name == Chat::Tools::AskSpecialist::NAME }.map(&:tool_call_id)
    return [] if asked.empty?

    own_chats = Chat::Helper.where(chat: chat, tool_call_id: asked).where.not(domain: nil).includes(:own_chat).filter_map(&:own_chat)
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: Chat::Message.where(chat: own_chats).select(:id))
                                   .where.not(result_id: nil).where(failed: false).where.not(name: Chat::Specialists::Report::NAME)
                                   .order(:created_at, :id).select { |call| read?(workspace, call.name, call.arguments) }
  end
  private_class_method :own_reads, :specialist_reads

  def self.backs?(call, started, fresh_from) = started.nil? || call.message.created_at >= started || call.message.created_at >= fresh_from

  # A read through any tool: one the page shows as looking something up, or a capability that only reads.
  def self.read?(workspace, name, arguments)
    return true if Chat::Tools.kind(name, workspace, arguments) == Chat::Tools::KIND_READ
    return true if [ Chat::Tools::KeyQuery::NAME, Chat::Tools::LogPatterns::NAME ].include?(name.to_s)

    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name.to_s }
    spec.present? && !spec.writes
  end

  def self.tool_name(entry) = entry[NAMED].to_s
end
