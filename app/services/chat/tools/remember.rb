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
        "about" => { "type" => "string", "description" => "The resource on the map or catalog entry it is about, by name, such as web or Checkout. Leave it out for the whole workspace" },
        "from_person" => { "type" => "boolean", "description" => "True only when the person asked you to remember this, in their own words. Leave it out for anything you worked out yourself" }
      },
      "required" => [ "fact" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    fact = asked["fact"].to_s.strip
    subject = Chat::Memory.subject_named(@agent_run.workspace, asked["about"], principal: @agent_run.acting_principal)
    # Only a chat has a person to vouch for it. In a run the flag means nothing.
    teacher = @agent_run.memory_teacher
    vouched = asked["from_person"] == true && teacher.present?
    Chat::Tools.memory_change(@agent_run, Ability::Action::ACTION_CREATE, tool_name: name, params: asked.slice("about", "from_person"), tool_call_id: tool_call&.id) do
      learned(fact, subject, teacher, vouched, asked["about"])
    end
  rescue ActiveRecord::RecordInvalid => error
    { error: error.record.errors.full_messages.to_sentence }
  end

  private

  def learned(fact, subject, teacher, vouched, about)
    learned = Chat::Memory.learn!(@agent_run.workspace, text: fact, subject: subject, source: @agent_run.memory_source, added_by: teacher, vouched: vouched)
    known = learned.memory
    case learned.outcome
    when Chat::Memory::LEARNED_REJECTED
      return "A person rejected this before#{": #{known.state_reason}" if known.state_reason.present?}. It is not saved again."
    when Chat::Memory::LEARNED_KNOWN
      return "Already remembered."
    end

    missing = about.present? && subject.nil? ? " Nothing called #{about} is on the map or in the catalog, so it is saved for the whole workspace." : ""
    "#{vouched ? "Remembered, confirmed by #{teacher.display_name}." : 'Remembered, unconfirmed until a person confirms it.'}#{missing}"
  end
end
