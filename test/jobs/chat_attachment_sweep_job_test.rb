require "test_helper"

class ChatAttachmentSweepJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "an upload nobody sent within a day is deleted with its bytes, and a sent or recent one stays" do
    abandoned = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "old.log", bytes: "old")
    abandoned.update_columns(created_at: 2.days.ago)
    recent = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "new.log", bytes: "new")
    sent = Chat::Attachment.take!(workspace: @workspace, uploaded_by: @member, filename: "sent.log", bytes: "sent")
    Conversation.start_personal!(workspace: @workspace, member: @member).ask!("look", files: [ sent ])
    sent.update_columns(created_at: 2.days.ago)

    assert_enqueued_with(job: ActiveStorage::PurgeJob) { ChatAttachmentSweepJob.perform_now }

    assert_not Chat::Attachment.exists?(abandoned.id)
    assert Chat::Attachment.exists?(recent.id)
    assert Chat::Attachment.exists?(sent.id)
  end
end
