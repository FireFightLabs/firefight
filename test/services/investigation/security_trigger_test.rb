require "test_helper"

class Investigation::SecurityTriggerTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(halon_monitoring_channel: "C_SECURITY")
    FirefightAi.stubs(:context_window).returns(200_000)
    @event = Integrations::SecurityEvents::Event.new(
      kind: Integrations::SecurityEvents::KIND_LEAKED_SECRET, provider: "GitHub", reference: "acme/web#12", place: "acme/web",
      what: "AWS Access Key ID", url: "https://github.com/acme/web/security/secret-scanning/12"
    )
  end

  def trigger = Investigation::SecurityTrigger.new(@workspace)

  test "a leaked secret starts Halon once, in the monitoring channel, asked what it reaches and how to replace it" do
    run = trigger.receive!(@event)

    assert_equal Investigation::TRIGGER_SECURITY_EVENT, run.trigger_source
    assert_equal "C_SECURITY", run.channel_id
    assert_nil run.subject
    assert_match "GitHub found a leaked AWS Access Key ID in acme/web (acme/web#12).", run.question
    assert_match "revoke and replace it", run.question
    assert_equal Investigation::Brief::SOURCE_SECURITY_EVENT, run.brief[Investigation::Brief::KEY_SOURCE]

    notice = @workspace.investigation_notices.sole
    assert_equal [ Investigation::Notice::SIGNAL_LEAKED_SECRET, run, 1 ], [ notice.signal, notice.investigation, notice.times_said ]

    facts = Investigation::QuestionSeed.new(run).gather[Investigation::QuestionSeed::KEY_SECURITY_EVENT]
    assert_equal Investigation::QuestionSeed::SECURITY_SKILL, facts["skill"]
    assert_match "suggest_incident", facts["incident"]
  end

  test "the same alert delivered again starts nothing, and the same alert found public starts Halon again" do
    first = trigger.receive!(@event)
    first.finish!(status: Investigation::STATUS_SUCCEEDED)

    assert_nil trigger.receive!(@event)
    again = trigger.receive!(@event.with(public: true))

    assert again
    assert_match "and it is public", again.question
    assert_equal Investigation::Notice::SEVERITY_HIGH, @workspace.investigation_notices.sole.severity
  end

  test "a second alert in the same repository is its own problem" do
    trigger.receive!(@event)

    assert trigger.receive!(@event.with(reference: "acme/web#13"))
    assert_equal 2, @workspace.investigation_notices.count
  end

  test "a workspace that turned it off starts nothing" do
    @workspace.update!(halon_security_events_enabled: false)

    assert_nil trigger.receive!(@event)
    assert_empty @workspace.investigation_notices
  end

  test "a delivery to a connection reaches its workspace's security module through a job" do
    github = @workspace.integrations.create!(provider: "github", name: "GitHub", slug: "github_sec", kind: Integration::KIND_NATIVE)
    row = github.integration_environments.create!(credentials: {}.to_json)
    payload = { "action" => "created", "repository" => { "full_name" => "acme/web" },
                "alert" => { "number" => 12, "secret_type_display_name" => "AWS Access Key ID" } }

    assert_enqueued_with(job: SecurityEventJob) do
      Integrations::MapEvents.report_security_events!([ row ], payload, headers: { "x-github-event" => "secret_scanning_alert" })
    end
    perform_enqueued_jobs(only: SecurityEventJob)

    assert_equal 1, @workspace.investigations.where(trigger_source: Investigation::TRIGGER_SECURITY_EVENT).count
  end
end
