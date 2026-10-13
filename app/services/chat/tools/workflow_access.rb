# What get_workflow and propose_workflow_edit share, both offered with the other workflow tools only where workflows are
# switched on (Conversation::Tools.workflows): the workflow named or the one the chat was started beside, and a refusal
# that marks the call failed.
module Chat::Tools::WorkflowAccess
  extend ActiveSupport::Concern

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  WORKFLOW_PARAMETER = {
    "type" => "string",
    "description" => "The workflow, by its id, slug, name or another name it goes by. Leave it out in a chat started beside a workflow's canvas"
  }.freeze

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  private

  def chosen_workflow(reference)
    if reference.present?
      scope = Workflow.where(workspace: @agent_run.workspace)
      wanted = reference.to_s.strip
      return (wanted.match?(UUID) && scope.find_by(id: wanted)) || Workflow.named(scope, wanted)
    end

    @agent_run.respond_to?(:conversation) ? @agent_run.conversation&.workflow : nil
  end

  def missing_workflow(reference)
    return "There is no workflow called #{reference} in this workspace." if reference.present?

    "Name the workflow, since this chat was not started beside one."
  end

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    words
  end
end
