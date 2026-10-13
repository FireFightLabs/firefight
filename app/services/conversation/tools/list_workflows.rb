# The workspace's workflows as Halon reads them: what each is called and goes by, what starts it, how it stands, when it
# runs next, how it last went and the inputs a run asks, so Halon runs the one a person names rather than redoing its
# steps by hand.
class Conversation::Tools::ListWorkflows < RubyLLM::Tool
  NAME = "list_workflows".freeze

  description "List the workspace's workflows: each one's name and other names, what starts it, whether it is live, when it runs " \
              "next, how its last run went, its steps and the inputs a run asks. Read it when the person names something the team " \
              "runs, such as a release, before doing its steps one by one."

  def self.tool_name = NAME

  def initialize(turn)
    super()
    @turn = turn
  end

  def name = NAME

  def parameters_schema = { "type" => "object", "properties" => {}, "required" => [] }

  def call(tool_call: nil, **)
    @turn.tool_call(action_key: Workflow::READ_KEY) { JSON.generate(Workflow::Listing.for(@turn.workspace)) }.value
  rescue AbilityGateway::Denied
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    "#{@turn.asker_name} may not read workflows."
  end
end
