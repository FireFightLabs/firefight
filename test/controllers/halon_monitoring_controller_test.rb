require "test_helper"

class HalonMonitoringControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Investigation.stubs(:available_for?).returns(true)
    Investigation.stubs(:start_refusal).returns(nil)
    @check = @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                                     hour: 9, time_zone: "Europe/Belgrade")
  end

  def form(**overrides)
    { name: "Certificates", kind: Investigation::Check::KIND_CERTIFICATES, cadence: Investigation::Check::CADENCE_WEEKLY, hour: 8, weekday: 1,
      time_zone: "Europe/Belgrade" }.merge(overrides)
  end

  test "any member sees the checks, what Halon raised, where it says it and what spend it can read" do
    sign_in(users(:bob), @workspace)
    Investigation::Notice.observe!(@workspace, Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "orders-db volume",
                                                                                  summary: "Full around Oct 28.", severity: Investigation::Notice::SEVERITY_MEDIUM))

    get halon_monitoring_path, headers: inertia_headers

    assert_response :success
    check = inertia_props["checks"].sole
    assert_equal [ "Disks", "Disk space", "Every day at 09:00 (Europe/Belgrade)", true ], check.values_at("name", "kindLabel", "schedule", "enabled")
    assert_equal "orders-db volume", inertia_props["notices"].sole["topic"]
    assert inertia_props["securityEventsEnabled"]
    assert inertia_props["spend"].key?("unread")
  end

  test "creating, updating, disabling, enabling and deleting a check each say so" do
    sign_in(users(:alice), @workspace)

    post investigation_checks_path, params: form
    assert_equal "Certificates was created.", flash[:notice]
    created = @workspace.investigation_checks.find_by!(name: "Certificates")
    assert_equal [ 1, users(:alice).id ], [ created.weekday, created.created_by.user_id ]

    patch investigation_check_path(created), params: { hour: 10 }
    assert_equal "Certificates was updated.", flash[:notice]
    assert_equal 10, created.reload.hour

    patch disable_investigation_check_path(created)
    assert_equal "Certificates is off.", flash[:notice]
    assert_not created.reload.enabled?

    patch enable_investigation_check_path(created)
    assert_equal "Certificates is on.", flash[:notice]
    assert created.reload.enabled?

    delete investigation_check_path(created)
    assert_equal "Certificates was deleted.", flash[:notice]
    assert_nil Investigation::Check.find_by(id: created.id)
  end

  test "a check that has runs is refused deletion with why" do
    sign_in(users(:alice), @workspace)
    @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400,
                                      status: Investigation::STATUS_SUCCEEDED)

    delete investigation_check_path(@check)

    assert_equal "Halon ran Disks 1 time, and those runs stay readable. Disable it instead.", flash[:alert]
    assert Investigation::Check.exists?(@check.id)
  end

  test "an invalid check comes back with its errors" do
    sign_in(users(:alice), @workspace)

    post investigation_checks_path, params: form(kind: Investigation::Check::KIND_CUSTOM)

    assert_nil @workspace.investigation_checks.find_by(name: "Certificates")
  end

  test "run now starts the check and says so, and a second press is refused while it runs" do
    sign_in(users(:alice), @workspace)

    assert_enqueued_jobs 1, only: InvestigationJob do
      post run_investigation_check_path(@check)
    end
    assert_equal "Halon is running Disks. It says what it finds when it is done.", flash[:notice]

    post run_investigation_check_path(@check)
    assert_equal "Disks is already running. Halon says what it finds when it is done.", flash[:alert]
  end

  test "the monitoring channel and the security trigger each say what changed" do
    sign_in(users(:alice), @workspace)

    patch halon_monitoring_path, params: { monitoring_channel: "#ops-alerts" }
    assert_equal "Halon now says what it finds in #ops-alerts.", flash[:notice]
    assert_equal "ops-alerts", @workspace.reload.halon_monitoring_channel

    patch halon_monitoring_path, params: { monitoring_channel: "" }
    assert_equal "The monitoring channel was cleared.", flash[:notice]

    patch halon_monitoring_path, params: { security_events_enabled: false }
    assert_equal "Halon no longer looks into leaked secrets.", flash[:notice]
    assert_not @workspace.reload.halon_security_events_enabled

    patch halon_monitoring_path, params: { security_events_enabled: true }
    assert_equal "Halon now looks into leaked secrets.", flash[:notice]
  end

  test "a member without a grant cannot change monitoring" do
    sign_in(users(:bob), @workspace)

    post investigation_checks_path, params: form

    assert_nil @workspace.investigation_checks.find_by(name: "Certificates")
  end
end
