# Look before you change. In a chat, a call that changes something names the reads from this same turn that show it
# will help, in BECAUSE, and the call is checked against the reads the turn really made. A change with none goes back to
# Halon before anyone is asked, and the confirmation shows the reads it named, so the person approves the reasoning and
# not only the call. Only a chat turn asks this. Investigations and watches only read, and a run nobody is in, such as a
# held call run once approved, keeps its own guards.
module Chat::Tools::LookFirst
  BECAUSE = "because".freeze
  DESCRIPTION = "Each read from this turn that shows this change will help, by the name of the tool you called, then what it " \
                "showed, such as \"northflank_list_deployments: web has run 7676c83 since 14:02, when errors started\". Only " \
                "reads you made in this turn count. Needed for any call that changes something".freeze
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
    [ BOUNCE, ("You named #{missing.to_sentence}, which you did not read in this turn." if missing.any?) ].compact.join(" ")
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

  # The calls of the turn running at until_at that read and answered. A turn starts at the person's latest message.
  def self.reads(chat, workspace, until_at: nil)
    person = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false)
    person = person.where(created_at: ..until_at) if until_at
    started = person.maximum(:created_at)
    messages = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT)
    messages = messages.where(created_at: started..) if started
    messages = messages.where(created_at: ..until_at) if until_at
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: messages.select(:id))
                                   .where.not(result_id: nil).where(failed: false).order(:created_at, :id)
                                   .select { |call| read?(workspace, call.name, call.arguments) }
  end

  # A read through any tool: one the page shows as looking something up, or a capability that only reads.
  def self.read?(workspace, name, arguments)
    return true if Chat::Tools.kind(name, workspace, arguments) == Chat::Tools::KIND_READ
    return true if [ Chat::Tools::KeyQuery::NAME, Chat::Tools::LogPatterns::NAME ].include?(name.to_s)

    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name.to_s }
    spec.present? && !spec.writes
  end

  def self.tool_name(entry) = entry[NAMED].to_s
end
