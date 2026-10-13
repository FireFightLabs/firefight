# A workflow Halon made from a chat, kept in step where it was made: the dashboard chat draws its card, and a chat in a
# thread keeps a message there that is redrawn as it moves. Run now and Cancel, pressed on either, go through the same
# moves as the workflow's own page, each with a sentence for the person.
module Conversation::Workflows
  Result = Data.define(:ok, :words)

  module_function

  # It moved: made, published, ran, ended, switched off. The page looks again and the thread's message is redrawn.
  def moved!(workflow)
    conversation = workflow.origin_conversation
    return unless conversation

    Conversation::LiveDelivery.workflow_moved(conversation)
    ChatWorkflowMessageJob.perform_later(workflow.id) if conversation.thread_id.present?
  end

  def run_now!(workflow, by:)
    blocked = workflow.run_now_blocked_reason(by)
    return Result.new(ok: false, words: blocked) if blocked

    WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: by)
    Result.new(ok: true, words: "#{workflow.name} is running.")
  rescue Workflow::Run::Refused => refused
    Result.new(ok: false, words: refused.message)
  end

  # A one off is cancelled before its time, and a repeating one turned off. Either way it does not run again on its own.
  def stop!(workflow, by:)
    blocked = workflow.stop_blocked_reason(by)
    return Result.new(ok: false, words: blocked) if blocked

    one_off = workflow.one_off?
    WorkflowPublishService.new(workflow).switch!(on: false)
    moved!(workflow)
    Result.new(ok: true, words: one_off ? "#{workflow.name} was cancelled. It will not run." : "#{workflow.name} is off.")
  end

  def press!(workflow, action, by:)
    return Result.new(ok: false, words: "Workflows are not switched on for this workspace.") unless FeatureFlags.enabled?(workflow.workspace, FeatureFlags::WORKFLOWS)

    case action
    when Workflow::ACTION_RUN_NOW then run_now!(workflow, by: by)
    when Workflow::ACTION_CANCEL, Workflow::ACTION_TURN_OFF then stop!(workflow, by: by)
    else Result.new(ok: false, words: workflow.chat_offer_blocked_reason(action, by))
    end
  end

  # Posts the message in the thread the first time and redraws it after.
  def tell!(workflow)
    conversation = workflow.origin_conversation
    return unless conversation&.thread_id.present?

    adapter = WorkspaceAdapter.for(workflow.workspace)
    if workflow.chat_message_id.present?
      adapter.update_chat_workflow(channel_id: workflow.chat_message_channel_id, message_id: workflow.chat_message_id, workflow: workflow)
    else
      posted = adapter.post_chat_workflow(channel_id: conversation.channel_id, thread_id: conversation.thread_id, workflow: workflow)
      workflow.update_columns(chat_message_channel_id: posted[:channel_id], chat_message_id: posted[:message_id])
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "chat_workflow.untold", workflow_id: workflow.id, error: error.class.name }.to_json)
  end
end
