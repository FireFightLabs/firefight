require "test_helper"
require "rake"
require Rails.root.join("lib/tasks/demo/readme_workspace").to_s

class DemoRakeTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 17)

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:readme")
    Rake::Task["demo:readme"].reenable
    @day = ENV["DAY"]
    ENV["DAY"] = DAY.iso8601
  end

  teardown do
    ENV["DAY"] = @day
  end

  test "it builds INC-042 with Halon's run, the fix Maya applied and the chat that asked, and names everyone as current code does" do
    assert_output(/Built Acme, with INC-042/) { Rake::Task["demo:readme"].invoke }

    workspace = Workspace.find_by!(platform: Platforms::SLACK, platform_id: Demo::ReadmeWorkspace::TEAM_ID)
    incident = workspace.incidents.sole
    assert_equal "INC-042", incident.identifier
    assert_equal [ IncidentSeverity::SLUG_CRITICAL, IncidentStatus::SLUG_IDENTIFIED ], [ incident.incident_severity.slug, incident.incident_status.slug ]
    assert_equal Demo::ReadmeWorkspace::LEAD[:name], incident.lead.display_name
    assert_equal [ "Sam Lee", "Priya Shah" ], incident.incident_subscriptions.order(:created_at).map { |subscription| subscription.workspace_membership.display_name }

    timeline = incident.incident_events.chronological.map { |event| [ event.event_type, event.actor&.actor_display_name || IncidentEvent::AUTOMATED_ACTOR_NAME ] }
    assert_equal [
      [ IncidentEvent::INCIDENT_CREATED, IncidentEvent::AUTOMATED_ACTOR_NAME ],
      [ IncidentEvent::ALERT_ATTACHED, IncidentEvent::AUTOMATED_ACTOR_NAME ],
      [ IncidentEvent::INVESTIGATION_STARTED, SystemAgent.investigator.name ],
      [ IncidentEvent::INVESTIGATION_ANSWERED, SystemAgent.investigator.name ],
      [ IncidentEvent::FIX_APPLIED, "Maya Ortiz" ],
      [ IncidentEvent::INCIDENT_UPDATED, "Maya Ortiz" ],
      [ IncidentEvent::ROLE_ASSIGNED, "Maya Ortiz" ],
      [ IncidentEvent::ROLE_ASSIGNED, "Maya Ortiz" ]
    ], timeline

    alert = workspace.alerts.sole
    assert_equal [ "Checkout 5xx rate above 5%", 14, incident ], [ alert.title, alert.event_count, alert.incident ]

    run = incident.investigations.sole
    assert_equal [ Investigation::STATUS_SUCCEEDED, 257, 5 ], [ run.status, run.duration_seconds, run.steps.count ]
    assert_equal Investigation::Finding::KIND_ROOT_CAUSE, run.finding.answer_kind
    assert_equal "Very sure", run.finding.sureness

    chats = workspace.conversations.order(:created_at).map(&:display_title)
    assert_equal [ "Today's checkout-api release", "Services on orders-db", "Card payments failing at checkout since 14:04" ], chats
    assert_equal run, workspace.conversations.find_by!(subject: incident).investigations.sole
  end

  test "a second run builds the workspace afresh" do
    capture_io { Rake::Task["demo:readme"].invoke }
    Rake::Task["demo:readme"].reenable
    capture_io { Rake::Task["demo:readme"].invoke }

    assert_equal 1, Workspace.where(platform: Platforms::SLACK, platform_id: Demo::ReadmeWorkspace::TEAM_ID).count
    assert_equal 1, User.where(email: Demo::ReadmeWorkspace::LEAD[:email]).count
  end

  test "it leaves nothing that would speak in Slack or call a model" do
    capture_io { Rake::Task["demo:readme"].invoke }

    incident = Workspace.find_by!(platform_id: Demo::ReadmeWorkspace::TEAM_ID).incidents.sole
    assert_not SolidWorkflow::Workflow.live.exists?(subject: incident)
    assert_equal Demo::ReadmeWorkspace::CHANNEL_ID, incident.channel_id
  end

  test "it refuses to run anywhere but development and test" do
    Rails.env.stubs(:local?).returns(false)

    assert_raises(SystemExit) { capture_io { Rake::Task["demo:readme"].invoke } }
    assert_not Workspace.exists?(platform_id: Demo::ReadmeWorkspace::TEAM_ID)
  end
end
