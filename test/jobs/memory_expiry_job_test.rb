require "test_helper"

class MemoryExpiryJobTest < ActiveJob::TestCase
  test "only a workspace that chose a window has its old unconfirmed memories expire" do
    chose = workspaces(:slack_workspace_one)
    chose.update!(memory_expiry_days: 60)
    kept = workspaces(:slack_workspace_two)
    stale = Chat::Memory.create!(workspace: chose, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    untouched = Chat::Memory.create!(workspace: kept, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)
    Chat::Memory.where(id: [ stale.id, untouched.id ]).update_all(updated_at: 61.days.ago)

    MemoryExpiryJob.perform_now

    assert_equal Chat::Memory::STATE_EXPIRED, stale.reload.state
    assert_equal Chat::Memory::STATE_UNCONFIRMED, untouched.reload.state
  end
end
