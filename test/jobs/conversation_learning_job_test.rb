require "test_helper"

class ConversationLearningJobTest < ActiveJob::TestCase
  setup do
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: workspaces(:slack_workspace_one), member: @member)
    @conversation.ask!("Where does web deploy from?")
    @conversation.update_columns(answer_owed_since: nil)
  end

  test "a chat quiet since its last turn is read" do
    ChatLearningService.any_instance.expects(:learn!).once

    ConversationLearningJob.perform_now(@conversation.id, 1.second.from_now)
  end

  test "a chat with something said since the turn that queued it is left to the newer turn's job" do
    ChatLearningService.any_instance.expects(:learn!).never

    ConversationLearningJob.perform_now(@conversation.id, 1.hour.ago)
  end

  test "a chat with an answer being written is not read" do
    @conversation.update_columns(answer_owed_since: Time.current)
    ChatLearningService.any_instance.expects(:learn!).never

    ConversationLearningJob.perform_now(@conversation.id, 1.second.from_now)
  end

  test "an archived chat is read at once, and a chat deleted meanwhile is skipped" do
    ChatLearningService.any_instance.expects(:learn!).once
    ConversationLearningJob.perform_now(@conversation.id)

    @conversation.destroy!
    assert_nothing_raised { ConversationLearningJob.perform_now(@conversation.id) }
  end
end
