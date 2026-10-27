# Records what the nightly memory check found for one memory it was handed: right, wrong or unsure, with the evidence.
# Right and wrong cite the steps that show it, so a verdict always rests on something Halon read tonight. What each
# verdict does, and what a person's decision protects, is the memory's own rule (Chat::Memory::Checking). It writes as
# the investigator through the gateway, so an admin who revokes its memory grant stops it and each verdict is in Activity.
class Investigation::Tools::SettleMemory < RubyLLM::Tool
  def self.tool_name = FirefightAi::MemoryChecker::SETTLE_TOOL

  def initialize(investigation)
    super()
    @investigation = investigation
  end

  def name = self.class.tool_name

  def description
    "Record what you found for one of tonight's memories. right when a read shows it holds, wrong when a read shows it " \
      "does not, unsure when you could not tell. Right and wrong name the steps that show it. Call #{FirefightAi::MemoryChecker::FINISH_TOOL} " \
      "once every memory is settled."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "memory" => { "type" => "string", "description" => "The memory's id, as memories_to_check gives it" },
        "verdict" => { "type" => "string", "enum" => Chat::Memory::VERDICTS, "description" => "right, wrong or unsure" },
        "evidence" => { "type" => "string", "description" => "What you read and what it showed, in one or two plain sentences a person " \
                                                              "can follow. For unsure, what you tried and why it did not settle it" },
        "steps" => { "type" => "array", "items" => { "type" => "integer" }, "description" => "The step numbers of the reads that show it. Needed for right and wrong" },
        "correction" => { "type" => "string", "description" => "For wrong, what is right instead as one plain sentence, when a read shows it (optional)" }
      },
      "required" => %w[memory verdict evidence]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    verdict = asked["verdict"].to_s.presence_in(Chat::Memory::VERDICTS)
    evidence = asked["evidence"].to_s.strip
    return refused(tool_call, "Say right, wrong or unsure in verdict.") unless verdict
    return refused(tool_call, "Say what you read and what it showed in evidence.") if evidence.blank?

    review = @investigation.memory_review
    memory = review && Chat::Memory.where(workspace: @investigation.workspace, id: review.memory_ids).find_by(id: asked["memory"].to_s)
    return refused(tool_call, "Memory #{asked['memory']} is not one of tonight's. Settle only those in memories_to_check.") unless memory

    @investigation.cited_steps!(asked["steps"], what: "This verdict") unless verdict == Chat::Memory::VERDICT_UNSURE
    Chat::Tools.memory_change(@investigation, Ability::Action::ACTION_UPDATE, tool_name: name, params: { "memory" => memory.id, "verdict" => verdict },
                                                                               tool_call_id: tool_call&.id) do
      settled = review.settle!(memory, verdict: verdict, evidence: evidence, correction: asked["correction"].to_s.strip.presence)
      next refused(tool_call, settled.words) unless settled.outcome

      settled.challenged.each { |id| MemoryChallengeJob.perform_later(id) }
      settled.words
    end
  rescue Investigation::Evidence::Refused, Chat::Memory::Refused => error
    refused(tool_call, "#{error.message} Nothing was changed.")
  rescue ActiveRecord::RecordInvalid => error
    refused(tool_call, "#{error.record.errors.full_messages.to_sentence} Nothing was changed.")
  end

  private

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@investigation, tool_call&.id)
    words
  end
end
