require "test_helper"

class HalonCheckSweepJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FirefightAi.stubs(:context_window).returns(200_000)
    @check = travel_to(Time.utc(2026, 10, 10, 6, 0)) do
      @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                              hour: 9, time_zone: "UTC", created_by: workspace_memberships(:alice_workspace_one))
    end
  end

  test "a due check whose owner left is paused instead of run, and admins are told once by direct message" do
    bob = workspace_memberships(:bob_workspace_one)
    @check.update_columns(owner_id: bob.id)
    bob.update_column(:removed_at, Time.current)
    told = []
    adapter = mock("adapter")
    adapter.stubs(:post_notice).with { |user_id:, notice:| told << [ user_id, notice ] }.returns(success: true)
    WorkspaceAdapter.stubs(:for).returns(adapter)

    travel_to Time.utc(2026, 10, 10, 9, 2) do
      perform_enqueued_jobs(only: CheckOwnerGoneJob) do
        HalonCheckSweepJob.perform_now
        HalonCheckSweepJob.perform_now
      end
    end

    assert_empty @check.investigations
    assert @check.reload.paused?
    assert_equal [ workspace_memberships(:alice_workspace_one).platform_user_id ], told.map(&:first)
    assert_equal "Disks (owned by #{bob.display_name}, who left) is paused. Give it a new owner to resume.", told.sole.last.title
    assert_equal "Open Monitoring", told.sole.last.link_label
  end

  test "admins nobody could be told about a paused check are tried again on the next sweep" do
    @check.update_columns(owner_id: nil, paused_at: Time.current)
    adapter = mock("adapter")
    adapter.stubs(:post_notice).raises(AdapterError, "Slack is down")
    WorkspaceAdapter.stubs(:for).returns(adapter)

    CheckOwnerGoneJob.perform_now(@check.id)

    assert_nil @check.reload.owner_gone_told_at
    assert_enqueued_with(job: CheckOwnerGoneJob, args: [ @check.id ]) { HalonCheckSweepJob.perform_now }
  end

  test "a telling that breaks before reaching anyone gives its claim back, so a retry or the next sweep tells them" do
    @check.update_columns(owner_id: nil, paused_at: Time.current)
    WorkspaceAdapter.stubs(:for).raises(RuntimeError, "no platform")

    assert_raises(RuntimeError) { CheckOwnerGoneJob.new.perform(@check.id) }

    assert_nil @check.reload.owner_gone_told_at
  end

  test "a check paused before the sweep, such as by the move to owners, has its admins told on the next sweep" do
    @check.update_columns(owner_id: nil, paused_at: Time.current)

    assert_enqueued_with(job: CheckOwnerGoneJob, args: [ @check.id ]) { HalonCheckSweepJob.perform_now }
  end

  test "a due check starts one scheduled run with the check as its subject, and its schedule moves on" do
    travel_to Time.utc(2026, 10, 10, 9, 2) do
      assert_enqueued_jobs 1, only: InvestigationJob do
        HalonCheckSweepJob.perform_now
        HalonCheckSweepJob.perform_now
      end
    end

    run = @check.investigations.sole
    assert_equal Investigation::TRIGGER_SCHEDULE, run.trigger_source
    assert run.scheduled?
    assert_equal Time.utc(2026, 10, 11, 9, 0), @check.reload.next_run_at
  end

  test "a check that is not due yet waits" do
    travel_to Time.utc(2026, 10, 10, 8, 59) do
      HalonCheckSweepJob.perform_now
    end

    assert_empty @check.investigations
  end

  test "a workspace that cannot run Halon starts nothing, and the schedule still moves on" do
    Investigation.stubs(:start_refusal).returns("AI features are not available.")

    travel_to(Time.utc(2026, 10, 10, 9, 2)) { HalonCheckSweepJob.perform_now }

    assert_empty @check.investigations
    assert_equal Time.utc(2026, 10, 11, 9, 0), @check.reload.next_run_at
  end

  test "a sweep reads each workspace, its model and its AI account once, however many of its checks are due" do
    workspace_reads = lambda do |count|
      travel_to(Time.utc(2026, 10, 10, 6, 0)) { count.times { |index| due_check("Disks #{index} #{SecureRandom.hex(2)}") } }
      sent = travel_to(Time.utc(2026, 10, 10, 9, 2)) { queries_sent { HalonCheckSweepJob.perform_now(Time.utc(2026, 10, 11, 9, 2)) } }
      sent.grep(/FROM "(workspaces|ai_model_overrides|workspace_ai_accounts)"/)
    end

    few = workspace_reads.call(1)
    many = workspace_reads.call(6)

    assert_equal few.size, many.size, repeated_queries(many)
    assert_equal 8, @workspace.investigation_checks.sum { |check| check.investigations.count }
  end

  private

  def due_check(name)
    @workspace.investigation_checks.create!(name: name, kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY, hour: 9, time_zone: "UTC",
                                            created_by: workspace_memberships(:alice_workspace_one))
  end
end
