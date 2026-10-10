# What every plan tool shares: the turn it acts in, finding the plan it means, and saying a refusal so the agent fixes it.
class Conversation::Tools::PlanTool < RubyLLM::Tool
  STEP = {
    "type" => "object",
    "properties" => {
      "description" => { "type" => "string", "description" => "What the step does, in a few plain words, such as Start the release workflow" },
      "kind" => { "type" => "string", "enum" => Chat::Plan::Step::KINDS,
                  "description" => "read looks something up, change changes something, check reads whether the changes worked" },
      "place" => { "type" => "string", "description" => "The system it happens in, such as GitHub or the checkout service (optional)" },
      "tool" => { "type" => "string", "description" => "The tool a change calls, by the name you call it. Required for every change in a scheduled plan (optional)" },
      "undo" => { "type" => "string", "description" => "For a change, how to put it back, written now before it runs, such as Roll back checkout to the deploy before" }
    },
    "required" => %w[description kind]
  }.freeze

  PLAN = { "type" => "string", "description" => "The plan's id. Needed only when the chat has more than one plan going" }.freeze

  def initialize(turn)
    super()
    @turn = turn
  end

  private

  def chat = @turn.chat

  # The plan named, or the one plan that fits when none is named.
  def find_plan(id, statuses)
    plans = chat ? chat.plans.where(status: statuses) : Chat::Plan.none
    return chat&.plans&.find_by(id: id.to_s) || refuse!("No plan #{id} in this chat.") if id.present?

    found = plans.to_a
    refuse!("No plan is going in this chat. Make one with make_plan.") if found.empty?
    refuse!("This chat has #{found.size} plans going (#{found.map(&:id).join(', ')}). Name the one you mean as plan.") if found.size > 1
    found.first
  end

  def refuse!(text) = raise(Chat::Plan::Refused, text)

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    text
  end

  def told(plan, text)
    Conversation::Plans.moved!(plan)
    "#{text}\n#{Conversation::Plans.described(plan.reload)}"
  end
end
