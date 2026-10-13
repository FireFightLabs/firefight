module Slack::WorkspaceAdapter::WorkflowMessaging
  extend ActiveSupport::Concern

  def post_workflow_publish_request_to_user(user_id:, request:)
    post_message(channel_id: user_id, text: Slack::Messages::WorkflowPublishRequest.fallback(request),
                 blocks: Slack::Messages::WorkflowPublishRequest.build(request))
  end

  def update_workflow_publish_request(channel_id:, message_id:, request:)
    update_message(channel_id: channel_id, message_id: message_id, text: Slack::Messages::WorkflowPublishRequest.fallback(request),
                   blocks: Slack::Messages::WorkflowPublishRequest.build(request))
    { success: true }
  end

  def post_workflow_publish_answer_to_user(user_id:, request:)
    post_message(channel_id: user_id, text: Slack::Messages::WorkflowPublishAnswer.fallback(request),
                 blocks: Slack::Messages::WorkflowPublishAnswer.build(request))
  end

  def post_workflow_failure(channel_id:, run:, suggestion:)
    post_message(channel_id: channel_id, text: Slack::Messages::WorkflowRunNotice.failed_fallback(run),
                 blocks: Slack::Messages::WorkflowRunNotice.failed(run, suggestion: suggestion))
  end

  def post_workflow_all_clear(channel_id:, run:)
    post_message(channel_id: channel_id, text: Slack::Messages::WorkflowRunNotice.all_clear_fallback(run),
                 blocks: Slack::Messages::WorkflowRunNotice.all_clear(run))
  end
end
