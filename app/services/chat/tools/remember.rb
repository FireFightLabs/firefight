# Saves a lasting fact about the setup for the next chat or run, marked unconfirmed until a person confirms it.
class Chat::Tools::Remember < RubyLLM::Tool
  def self.tool_name = "remember"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Save a lasting fact about this workspace's setup that would save the next chat or run time, such as which database " \
      "is production or which service handles payments. It is used at once, marked unconfirmed until a person confirms it. " \
      "Never save live values (a count, an error rate, what is failing now), secrets, or anything about a person."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "fact" => { "type" => "string", "description" => "The fact in one plain sentence, at most #{Chat::Memory::TEXT_LIMIT} characters" },
        "about" => { "type" => "string", "description" => "The resource on the map or catalog entry it is about, by name or id, such as web or Checkout. Leave it out only when it is about the whole workspace" },
        "from_person" => { "type" => "boolean", "description" => "True only when the person asked you to remember this, in their own words. Leave it out for anything you worked out yourself" },
        "seen_in" => { "type" => "string", "description" => "Where a result showed it, such as the deploy log of web or the checkout service's settings. Leave it out when the person told you" }
      },
      "required" => [ "fact" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    fact = asked["fact"].to_s.strip
    named = Chat::Memory.subject_named(@agent_run.workspace, asked["about"], principal: @agent_run.acting_principal)
    return refused(tool_call, "#{named.refusal} Nothing was saved. Name what it is about, or leave about out to save it for the whole workspace.") if named.refusal

    subject = named.subject
    # Only a chat has a person to vouch for it. In a run the flag means nothing.
    teacher = @agent_run.memory_teacher
    vouched = asked["from_person"] == true && teacher.present?
    seen_in = asked["seen_in"].to_s.strip.presence
    Chat::Tools.memory_change(@agent_run, Ability::Action::ACTION_CREATE, tool_name: name, params: asked.slice("about", "from_person"), tool_call_id: tool_call&.id) do
      learned(fact, subject, teacher, vouched, seen_in, tool_call)
    end
  rescue ActiveRecord::RecordInvalid => error
    refused(tool_call, error.record.errors.full_messages.to_sentence)
  end

  private

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    words
  end

  def learned(fact, subject, teacher, vouched, seen_in, tool_call)
    judge = FirefightAi::MemoryJudge.new(@agent_run.workspace, inferable: @agent_run.chat_owner, member: teacher)
    learned = Chat::Memory.learn!(@agent_run.workspace, text: fact, subject: subject, source: @agent_run.memory_source, added_by: teacher, vouched: vouched,
                                                        judge: judge, contradiction: contradiction(fact, teacher, vouched, seen_in))
    known = learned.memory
    case learned.outcome
    when Chat::Memory::LEARNED_REFUSED then return refused(tool_call, learned.reason)
    when Chat::Memory::LEARNED_REJECTED
      return refused(tool_call, "A person rejected this before#{": #{known.state_reason}" if known.state_reason.present?}. It is not saved again.")
    when Chat::Memory::LEARNED_KNOWN
      return "Already remembered."
    end

    Chat::Tools.tell_incident(@agent_run, known, Chat::MemoryPost::KIND_LEARNED)
    learned.contradicted.each { |memory| Chat::Tools.raise_dispute(@agent_run, memory, evidence: evidence(fact, vouched, seen_in)) }
    [ vouched ? "Remembered, confirmed by #{teacher.display_name}." : "Remembered, unconfirmed until a person confirms it.",
      *learned.contradicted.map { |memory| contradicted_words(memory) } ].join(" ")
  end

  # Why the memory it contradicts is disputed, as the Memory page and an incident's channel read it.
  def contradiction(fact, teacher, vouched, seen_in)
    return "#{seen_in.upcase_first} shows \"#{fact}\"." if seen_in
    return "#{teacher.display_name} said \"#{fact}\"." if vouched

    nil
  end

  # The same, as the card in the person's own chat says it.
  def evidence(fact, vouched, seen_in)
    return "#{seen_in.upcase_first} shows \"#{fact}\"." if seen_in
    return "You told me \"#{fact}\"." if vouched

    "I just learned \"#{fact}\"."
  end

  def contradicted_words(memory)
    "It contradicts memory #{memory.id} (\"#{memory.text}\"), which is now disputed and not used until a person decides which is right. " \
      "Say so, and which one you trust more and why."
  end
end
