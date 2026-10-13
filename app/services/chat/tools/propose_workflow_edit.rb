# Proposes one change to a workflow, made of one or more edits that a person accepts or dismisses together on the
# canvas. Nothing a run does changes until then, except while Halon builds a draft nobody else has touched and nothing
# is live, where it lands in the draft and Undo takes it back. Authorized as a change to workflows, so whoever Halon acts
# for must be able to change them.
class Chat::Tools::ProposeWorkflowEdit < RubyLLM::Tool
  include Chat::Tools::WorkflowAccess

  NAME = "propose_workflow_edit".freeze
  MAX_EDITS = 30

  PAYLOADS = {
    Workflow::Edit::OPERATION_ADD_STEP => '{"step": {"name": "check_web", "kind": "delay", "config": {...}}, "within": "<a for each\'s id, to add it inside>"}. Give a new step an id of your own to connect it in the same change',
    Workflow::Edit::OPERATION_REMOVE_STEP => '{"step_id": "..."}',
    Workflow::Edit::OPERATION_CONNECT => '{"from": "<step id>", "to": "<step id>", "route": "<a route the step takes, such as yes>", "within": "<for each id>"}',
    Workflow::Edit::OPERATION_DISCONNECT => "the same as connect",
    Workflow::Edit::OPERATION_CHANGE_CONFIG => '{"step_id": "...", "changes": {"config": {<only the settings that change>}, "timeout_seconds": 60, "retry": {"max_attempts": 3}, "on_failure": "continue"}}, or {"changes": {"outputs": {...}}} for what the workflow hands back',
    Workflow::Edit::OPERATION_CHANGE_TRIGGER => '{"trigger": {<the whole trigger>}}',
    Workflow::Edit::OPERATION_RENAME => '{"step_id": "...", "name": "new_name"}, which rewrites every {{steps.<old>...}} reference, or {"name": "New name"} for the workflow'
  }.freeze

  def name = NAME

  def description
    "Propose a change to a workflow, such as adding a step, connecting two, changing a step's settings or the trigger. " \
      "The person sees it on the canvas, struck through or dashed, and accepts or dismisses it, so nothing changes on your " \
      "word alone. Group the edits one idea needs, such as a step and its connections, into one call. Read the workflow " \
      "with #{Chat::Tools::GetWorkflow::NAME} first and name steps by their ids. Each edit is an operation and its payload: " \
      "#{PAYLOADS.map { |operation, payload| "#{operation} #{payload}" }.join('; ')}."
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "workflow" => WORKFLOW_PARAMETER,
        "edits" => {
          "type" => "array", "maxItems" => MAX_EDITS,
          "items" => {
            "type" => "object",
            "properties" => {
              "operation" => { "type" => "string", "enum" => Workflow::Edit::OPERATIONS },
              "payload" => { "type" => "object", "description" => "What the operation changes, shaped as the description says" }
            },
            "required" => [ "operation", "payload" ]
          }
        },
        "reason" => { "type" => "string", "description" => "Why, in one sentence the person reads beside the change, such as \"Pages the owner when the check fails twice.\"" }
      },
      "required" => [ "edits", "reason" ]
    }
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.deep_stringify_keys
    workflow = chosen_workflow(asked["workflow"])
    return refused(tool_call, missing_workflow(asked["workflow"])) unless workflow

    edits = Array(asked["edits"]).select { |edit| edit.is_a?(Hash) }
    return refused(tool_call, "Give at least one edit.") if edits.empty?
    return refused(tool_call, "Propose at most #{MAX_EDITS} edits at once.") if edits.size > MAX_EDITS
    return refused(tool_call, "Say why, in one sentence.") if asked["reason"].to_s.strip.empty?

    made = @agent_run.tool_call(action_key: Ability::Action::WORKFLOWS_CREATE, params: { workflow: workflow.slug, edits: edits.size },
                                tool_name: name, label: "Propose a change to #{workflow.name}") do
      workflow.propose_from_chat!(edits, reason: asked["reason"].to_s.strip, chat: @agent_run.chat)
    end
    said(made.value)
  rescue Workflow::Edit::Refused => refusal
    refused(tool_call, "#{refusal.message} Nothing was proposed.")
  rescue AbilityGateway::Denied => denied
    refused(tool_call, @agent_run.refusal(denied.action_key))
  rescue AbilityGateway::PendingApproval
    Chat::Tools.waiting_for_approval(Ability::Action::WORKFLOWS_CREATE)
  end

  private

  def said(edits)
    return "Made in the draft, since nobody else has changed it and nothing is live. Undo on the canvas takes it back." if edits.none?(&:proposed?)

    "Proposed. The person sees it on the canvas and accepts or dismisses it, and the workflow stays as it is until then."
  end
end
