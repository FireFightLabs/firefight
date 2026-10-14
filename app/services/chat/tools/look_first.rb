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
  # Said with every refusal, so Halon tells the person what is missing rather than proposing the same change again.
  STUCK = "When no read you can make shows it, tell the person in plain words what you could not confirm and what would " \
          "let you, rather than proposing it again.".freeze
  # Said when the specialists asked in this turn read something. Halon makes the same read itself, and the read is
  # loaded by name once a specialist has made it (Chat::Specialists.made_names).
  SPECIALISTS_READ = "The specialists you asked read with %<reads>s. Make the read this rests on yourself, loading it by " \
                     "naming it in open_tools' tools, then name it in because.".freeze
  # Said when the change named asking a specialist, which is another model's words and never a read.
  REPORT_NOT_A_READ = "#{Chat::Helper::ASK_SPECIALIST} is a specialist's report, not a read of yours.".freeze
  # How many of the specialists' reads a refusal names.
  SPECIALIST_READS_NAMED = 6
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

  # Firefight's own tools and capabilities this asks, by name: a capability that writes and a tool that ends something.
  def self.firefight_change?(name)
    named = name.to_s
    Integrations::Capabilities::SPECS.values.any? { |spec| spec.writes && spec.tool_name == named } ||
      Mcp::Tools.all.any? { |tool_class| tool_class.ends_something? && tool_class.name_value.to_s == named }
  end

  def self.named(given) = Array(given.to_h.stringify_keys[BECAUSE]).map { |entry| entry.to_s.strip }.reject(&:empty?)

  # Why the change goes back to Halon, or nil when a read from this turn backs it. A call already put to the person passed
  # this when it was asked, so it is never sent back after their answer.
  def self.refusal(agent_run, given, tool_call_id: nil)
    return unless applies?(agent_run)

    workspace = agent_run.workspace
    refusal_in(agent_run.chat, given, tool_call_id: tool_call_id, read: ->(name, arguments) { read?(workspace, name, arguments) })
  end

  # The same check over any chat, read saying whether a call only read. A replay asks it with its scenario's word for
  # that (Conversation::Rehearsal::RecordedTool).
  def self.refusal_in(chat, given, read:, tool_call_id: nil)
    return if tool_call_id && chat.tool_calls.where(tool_call_id: tool_call_id).where.not(approval: nil).exists?

    entries = named(given)
    made = reads(chat, read: read).map { |call| call.name.downcase }.to_set
    backed, unread = entries.partition { |entry| made.include?(tool_name(entry).downcase) }
    return if backed.any?

    not_reads, missing = unread.map { |entry| tool_name(entry) }.uniq.partition { |name| NOT_READS.include?(name) }
    [ BOUNCE, (REPORT_NOT_A_READ if not_reads.include?(Chat::Helper::ASK_SPECIALIST)),
      ("You named #{missing.to_sentence}, which you did not read in this turn or recently enough." if missing.any?),
      specialists_read(chat), STUCK ].compact.join(" ")
  end

  # The reads the specialists made since the answer before this turn, which are the ones Halon makes again to back the
  # change.
  def self.specialists_read(chat)
    names = Chat::Specialists.made_names(chat, since: window(chat).last).to_a
    return if names.empty?

    shown = names.first(SPECIALIST_READS_NAMED)
    shown << "#{names.size - shown.size} more" if names.size > shown.size
    format(SPECIALISTS_READ, reads: shown.to_sentence)
  end

  # The reads a change put to the person named, each as the step is titled and what Halon said it showed, from the turn
  # the call was made in.
  def self.support(chat, tool_call, workspace)
    message = tool_call.try(:message)
    entries = named(tool_call.arguments)
    return [] if chat.nil? || message.nil? || entries.empty?

    calls = reads(chat, read: ->(name, arguments) { read?(workspace, name, arguments) }, until_at: message.created_at).group_by { |call| call.name.downcase }
    entries.filter_map do |entry|
      name = tool_name(entry)
      call = calls[name.downcase]&.last
      next unless call

      said = entry.delete_prefix(name).sub(/\A[\s:,.-]+/, "")
      Support.new(label: Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name, said: said)
    end
  end

  # The calls that read and answered in the turn running at until_at, which starts at the person's latest message, and
  # those of the answer before it made within PROPOSAL_FRESH_FOR of until_at. Only Halon's own reads count. A
  # specialist's report is outside text another model wrote, so neither ask_specialist nor what a specialist read
  # backs a change, and Halon confirms the finding a change rests on itself, with the same read when it needs to.
  def self.reads(chat, read:, until_at: nil)
    started, fresh_from, from = window(chat, until_at: until_at)
    messages = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT)
    messages = messages.where(created_at: from..) if from
    messages = messages.where(created_at: ..until_at) if until_at
    RubyLLM::ActiveRecord::ToolCall.where(message_type: Chat::Message.polymorphic_name, message_id: messages.select(:id))
                                   .where.not(result_id: nil).where(failed: false).includes(:message).order(:created_at, :id)
                                   .select { |call| backs?(call, started, fresh_from) && read.call(call.name, call.arguments) }
  end

  # When the turn running at until_at started, from when its previous answer's reads are fresh, and the earliest moment
  # a read that counts could have been made.
  def self.window(chat, until_at: nil)
    person = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false)
    person = person.where(created_at: ..until_at) if until_at
    started, before = person.reorder(created_at: :desc).limit(2).pluck(:created_at)
    [ started, (until_at || Time.current) - PROPOSAL_FRESH_FOR, (before || started if started) ]
  end

  def self.backs?(call, started, fresh_from) = started.nil? || call.message.created_at >= started || call.message.created_at >= fresh_from

  # A read through any tool: one the page shows as looking something up, or a capability that only reads. Asking a
  # specialist is never one, since its answer is another model's words, and nor is Halon's own theory board.
  NOT_READS = [ Chat::Tools::AskSpecialist::NAME, Chat::Tools::Theories::NAME ].freeze

  def self.read?(workspace, name, arguments)
    return false if NOT_READS.include?(name.to_s)
    return true if Chat::Tools.kind(name, workspace, arguments) == Chat::Tools::KIND_READ
    return true if [ Chat::Tools::KeyQuery::NAME, Chat::Tools::LogPatterns::NAME ].include?(name.to_s)

    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name.to_s }
    spec.present? && !spec.writes
  end

  def self.tool_name(entry) = entry[NAMED].to_s
end
