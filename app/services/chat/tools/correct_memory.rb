# A person telling Halon a memory is wrong, or to forget it. Only a chat has a person, so a run never holds it.
class Chat::Tools::CorrectMemory < RubyLLM::Tool
  def self.tool_name = "correct_memory"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "When the person says a memory is wrong, or asks you to forget it, reject it. Give their correction when they said " \
      "what is right instead, and it replaces the memory as confirmed by them. A rejected memory is kept so it is never " \
      "learned again. Use it only for what the person said. For your own doubt, use dispute_memory."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "memory" => { "type" => "string", "description" => "The memory's id, as recall or the start of the chat shows it" },
        "reason" => { "type" => "string", "description" => "Why it is wrong, in the person's words" },
        "correction" => { "type" => "string", "description" => "What is right instead, when the person said it, as one plain sentence (optional)" }
      },
      "required" => [ "memory", "reason" ]
    }
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    memory = Chat::Memory.where(workspace: @agent_run.workspace).find_by(id: asked["memory"].to_s)
    return "There is no memory #{asked['memory']}." unless memory

    Chat::Tools.memory_change(@agent_run, Ability::Action::ACTION_UPDATE, tool_name: name, params: asked.slice("memory"), tool_call_id: tool_call&.id) do
      outcome = memory.reject!(by: @agent_run.memory_teacher, reason: asked["reason"].to_s.strip, correction: asked["correction"].to_s.strip)
      next memory.reject_blocked_reason unless outcome

      outcome == memory ? "Forgotten. It is kept as rejected, so it is not learned again." : "Corrected. The old one is rejected, and this replaces it, confirmed by #{@agent_run.memory_teacher&.display_name || 'the person'}."
    end
  rescue ActiveRecord::RecordInvalid => error
    { error: error.record.errors.full_messages.to_sentence }
  end
end
