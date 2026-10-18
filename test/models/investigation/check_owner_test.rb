require "test_helper"

# A scheduled check runs in its owner's name, so what it reads is bounded by them, as a run they started would be. An
# owner who leaves pauses it until an admin gives it a new one.
class Investigation::CheckOwnerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include TwoEnvironmentMapHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
    @check = @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                                     hour: 9, time_zone: "UTC", created_by: @bob)
  end

  test "a check is owned by whoever made it" do
    assert_equal @bob, @check.owner
  end

  test "a scheduled run is bounded by the check's owner, their map reach and their own grants" do
    limit_map_to(@workspace, @bob, catalog_entries(:production_env))
    agent = scheduled_run.acting_principal

    assert_equal @bob, agent.acting_for
    assert_equal %w[orders-db web], ResourceMap::Resource.visible_to(agent, @workspace).order(:name).pluck(:name)
  end

  test "a scheduled run is told which environments its owner reads, and to say plainly what it cannot reach" do
    limit_map_to(@workspace, @bob, catalog_entries(:production_env))

    reach = Investigation::CheckSeed.new(scheduled_run).gather.dig("check", "runs_within")

    assert_match "Bob", reach
    assert_match catalog_entries(:production_env).name, reach
    assert_match Investigation::CheckSeed::CANNOT_REACH, reach
  end

  test "a Run now run is told the reach of whoever pressed it, not the owner's" do
    limit_map_to(@workspace, @bob, catalog_entries(:production_env))
    pressed = @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, triggered_by: @alice,
                                                max_turns: 10, max_spend_cents: 400)

    reach = Investigation::CheckSeed.new(pressed).gather.dig("check", "runs_within")

    assert_match @alice.display_name, reach
    assert_match "on the map every environment.", reach
  end

  test "a run whose owner left is told it reaches nothing" do
    @bob.update_column(:removed_at, Time.current)

    reach = Investigation::CheckSeed.new(scheduled_run).gather.dig("check", "runs_within")

    assert_match "reaches nothing", reach
  end

  test "a scheduled run whose owner is gone reaches nothing" do
    @bob.update_column(:removed_at, Time.current)

    assert_empty ResourceMap::Resource.visible_to(scheduled_run.acting_principal, @workspace)
  end

  test "an owner who left pauses the check once, and admins are told once" do
    @bob.update_column(:removed_at, Time.current)

    assert @check.reload.owner_gone?
    assert @check.pause_for_gone_owner!
    assert_not @check.pause_for_gone_owner!, "a second pause changes nothing"
    assert @check.reload.paused?
    assert_equal "Disks (owned by #{@bob.display_name}, who left) is paused. Give it a new owner to resume.", @check.paused_because
    assert @check.claim_owner_gone_notice!
    assert_not @check.claim_owner_gone_notice!
    assert_equal @check.paused_because, @check.run_now_blocked_reason
    assert_not Investigation::Check.due(1.year.from_now).exists?(id: @check.id), "a paused check is never due"
  end

  test "handing a paused check to a member resumes it, and a former member cannot take it" do
    @bob.update_column(:removed_at, Time.current)
    @check.pause_for_gone_owner!

    assert_equal "Bob is not a member of this workspace any more.", @check.reload.hand_to_blocked_reason(@bob.reload).sub(@bob.display_name, "Bob")
    @check.hand_to!(@alice)

    assert_equal @alice, @check.reload.owner
    assert_not @check.paused?
    assert_nil @check.paused_because
    assert Investigation::Check.due(1.year.from_now).exists?(id: @check.id)
  end

  test "checks from before owners take their creator, and one whose creator is gone is paused" do
    orphan = @workspace.investigation_checks.create!(name: "Certificates", kind: Investigation::Check::KIND_CERTIFICATES, cadence: Investigation::Check::CADENCE_DAILY,
                                                     hour: 9, time_zone: "UTC", created_by: @alice)
    Investigation::Check.where(id: [ @check.id, orphan.id ]).update_all(owner_id: nil)
    Investigation::Check.where(id: orphan.id).update_all(created_by_id: nil)

    Investigation::Check.adopt_creators!

    assert_equal @bob, @check.reload.owner
    assert_not @check.paused?
    assert orphan.reload.paused?
    assert_equal "Certificates (owned by a former member, who left) is paused. Give it a new owner to resume.", orphan.paused_because
  end

  test "removing the owner pauses their checks at once, and the admins are told" do
    assert_enqueued_with(job: CheckOwnerGoneJob, args: [ @check.id ]) do
      MembershipRemoval.remove!(@bob, by: @alice)
    end

    assert @check.reload.paused?
    assert_equal "Disks (owned by #{@bob.display_name}, who left) is paused. Give it a new owner to resume.", @check.paused_because
  end

  test "a pause read before a handover changes nothing once the check has its new owner" do
    stale = Investigation::Check.find(@check.id)
    @bob.update_column(:removed_at, Time.current)
    Investigation::Check.find(@check.id).hand_to!(@alice)

    assert_not stale.pause_for_gone_owner!
    assert_not @check.reload.paused?
    assert_equal @alice, @check.owner
  end

  test "a handover read before another one lands changes nothing, so two cannot cross" do
    stale = Investigation::Check.find(@check.id)
    assert Investigation::Check.find(@check.id).hand_to!(@alice)

    assert_not stale.hand_to!(workspace_memberships(:alice_workspace_one))
    assert_not stale.hand_to!(@alice), "still stale, since it read Bob as the owner"
  end

  private

  def scheduled_run
    @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)
  end
end
