# Marks a memory a live result contradicted, so it is not used again until a person decides.
class Chat::Tools::DisputeMemory < RubyLLM::Tool
  def self.tool_name = "dispute_memory"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Mark a memory as disputed when a result you read contradicts it. It stops being used until a person confirms or " \
      "rejects it. Say what showed it wrong, with the step it came from."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "memory" => { "type" => "string", "description" => "The memory's id, as recall or the start of the chat shows it" },
        "reason" => { "type" => "string", "description" => "What showed it wrong, in one sentence" }
      },
      "required" => [ "memory", "reason" ]
    }
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    memory = Chat::Memory.visible_to(@agent_run.acting_principal, @agent_run.workspace).find_by(id: asked["memory"].to_s)
    return "There is no memory #{asked['memory']}." unless memory
    Chat::Tools.memory_change(@agent_run, Ability::Action::ACTION_UPDATE, tool_name: name, params: asked.slice("memory"), tool_call_id: tool_call&.id) do
      next "It is #{memory.state} already, so it is not in use." unless memory.dispute!(asked["reason"].to_s.strip)

      Chat::Tools.tell_incident(@agent_run, memory, Chat::MemoryPost::KIND_DISPUTED)
      "Disputed. It is not used again until a person confirms or rejects it."
    end
  end
end
