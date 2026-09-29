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
    subject = Chat::Memory.subject_named(@agent_run.workspace, asked["about"])
    known = Chat::Memory.where(workspace: @agent_run.workspace, subject: subject).to_a.find { |memory| memory.text.casecmp?(fact) }
    return "A person rejected this before#{": #{known.state_reason}" if known.state_reason.present?}. It is not saved again." if known&.state == Chat::Memory::STATE_REJECTED
    return "Already remembered." if known

    # Only a chat has a person to vouch for it. In a run the flag means nothing.
    teacher = @agent_run.memory_teacher
    vouched = asked["from_person"] == true && teacher
    Chat::Memory.create!(workspace: @agent_run.workspace, text: fact, subject: subject, source: @agent_run.memory_source, added_by: teacher,
                         state: vouched ? Chat::Memory::STATE_CONFIRMED : Chat::Memory::STATE_UNCONFIRMED,
                         confirmed_by: (teacher if vouched), confirmed_at: (Time.current if vouched))
    missing = asked["about"].present? && subject.nil? ? " Nothing called #{asked['about']} is on the map or in the catalog, so it is saved for the whole workspace." : ""
    "#{vouched ? "Remembered, confirmed by #{teacher.display_name}." : 'Remembered, unconfirmed until a person confirms it.'}#{missing}"
  rescue ActiveRecord::RecordInvalid => error
    { error: error.record.errors.full_messages.to_sentence }
  end
end
