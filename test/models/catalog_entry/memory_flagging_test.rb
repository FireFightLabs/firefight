require "test_helper"

class CatalogEntry::MemoryFlaggingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @entry = catalog_entries(:auth_service)
    @memory = Chat::Memory.create!(workspace: @workspace, text: "Auth Service keeps sessions in Redis", subject: @entry, state: Chat::Memory::STATE_CONFIRMED)
    @rejected = Chat::Memory.create!(workspace: @workspace, text: "Auth Service uses MySQL", subject: @entry, state: Chat::Memory::STATE_REJECTED)
  end

  test "renaming an entry flags what was remembered about it, and leaves a rejected memory rejected" do
    @entry.update!(name: "Identity Service")

    assert_equal [ Chat::Memory::STATE_OUTDATED, "Auth Service was renamed Identity Service", Chat::Memory::OUTDATED_RENAMED ],
                 @memory.reload.values_at(:state, :state_reason, :outdated_cause)
    assert_equal Chat::Memory::STATE_REJECTED, @rejected.reload.state
  end

  test "archiving an entry, alone or with its type, flags what was remembered about it" do
    @entry.soft_delete!
    assert_equal [ Chat::Memory::STATE_OUTDATED, "Auth Service was archived in the catalog" ], @memory.reload.values_at(:state, :state_reason)

    other = catalog_entries(:platform_team)
    about_team = Chat::Memory.create!(workspace: @workspace, text: "Platform owns the cluster", subject: other, state: Chat::Memory::STATE_UNCONFIRMED)
    other.catalog_type.stubs(:deletion_blocked_reason).returns(nil)
    other.catalog_type.soft_delete!
    assert_equal Chat::Memory::STATE_OUTDATED, about_team.reload.state
    assert_match "was archived", about_team.state_reason
  end

  test "other edits leave memories as they were" do
    @entry.update!(source: "backstage", external_id: "auth")

    assert_equal Chat::Memory::STATE_CONFIRMED, @memory.reload.state
  end
end
