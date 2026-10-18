require "test_helper"

# What the Monitoring page costs the database. Each check shows its latest run, that run's finding and whether a run is
# going, so more checks must not mean more queries.
class HalonMonitoringQueriesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Investigation.stubs(:available_for?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page costs the same for many checks as for a few, each with runs" do
    checks(3)
    get halon_monitoring_path, headers: inertia_headers
    few = queries_sent { get halon_monitoring_path, headers: inertia_headers }
    checks(15)
    many = queries_sent { get halon_monitoring_path, headers: inertia_headers }

    assert_response :success
    assert_same_queries few, many
  end

  test "each check shows its latest run, its finding and whether one is going, as before" do
    running, idle = checks(2)
    idle.investigations.live.update_all(status: Investigation::STATUS_SUCCEEDED)

    get halon_monitoring_path, headers: inertia_headers

    shown = inertia_props["checks"].index_by { |each| each["id"] }
    latest = running.investigations.seen.order(created_at: :desc).first
    assert_equal({ "id" => latest.id.to_s, "status" => latest.status, "at" => latest.created_at.iso8601, "summary" => "Disk 0 fills up" },
                 shown[running.id.to_s]["lastRun"])
    assert_equal "#{running.name} #{Investigation::Check::ALREADY_RUNNING}", shown[running.id.to_s]["runBlockedReason"]
    assert_nil shown[idle.id.to_s]["runBlockedReason"]
  end

  private

  def checks(count)
    Array.new(count) do |index|
      check = @workspace.investigation_checks.create!(name: "Disks #{SecureRandom.hex(3)}", kind: Investigation::Check::KIND_DISK,
                                                      cadence: Investigation::Check::CADENCE_DAILY, hour: 9, time_zone: "Europe/Belgrade", created_by: workspace_memberships(:alice_workspace_one))
      2.times do |run_index|
        run = @workspace.investigations.create!(subject: check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400,
                                                status: Investigation::STATUS_SUCCEEDED, created_at: (10 - run_index).minutes.ago)
        run.create_finding!(summary: "Disk #{index} fills up")
      end
      @workspace.investigations.create!(subject: check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400,
                                        status: Investigation::LIVE_STATUSES.first, rehearsal: true)
      check
    end
  end
end
