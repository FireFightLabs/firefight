require "test_helper"

class WatchSweepJobTest < ActiveJob::TestCase
  setup do
    workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    chat = Conversation.start_personal!(workspace: workspace, member: member).chat_record
    watch = ->(title, **columns) { Chat::Watch.create!(chat: chat, workspace: workspace, asker: member, title: title, expires_at: 1.hour.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT, **columns) }
    @due = watch.("due", checked_at: 2.minutes.ago)
    @fresh = watch.("fresh", checked_at: 10.seconds.ago)
    @ended = watch.("ended", status: Chat::Watch::STATUS_SUCCEEDED)
  end

  test "each active watch not checked within the minute is checked, so a restart loses nothing" do
    WatchSweepJob.perform_now

    assert_enqueued_jobs 1, only: WatchCheckJob
    assert_enqueued_with(job: WatchCheckJob, args: [ @due.id ])
  end
end
