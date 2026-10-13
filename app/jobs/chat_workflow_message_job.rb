# Posts or redraws the message a workflow made from a chat keeps in the chat's thread, one at a time per workflow.
class ChatWorkflowMessageJob < ApplicationJob
  queue_as :conversations
  limits_concurrency key: ->(workflow_id) { workflow_id }, duration: 2.minutes

  def perform(workflow_id)
    workflow = Workflow.find_by(id: workflow_id)
    Conversation::Workflows.tell!(workflow) if workflow
  end
end
