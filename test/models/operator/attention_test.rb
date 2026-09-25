require "test_helper"

class Operator::AttentionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a run that failed on our side opens its trace, and one that reached its budget is there to tune" do
    failed = run!(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")
    budget = run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT)

    ours = item_for(Operator::Attention::KIND_HALON_FAILED, failed)
    tune = item_for(Operator::Attention::KIND_HALON_LIMIT, budget)

    assert_equal Operator::IncidentProcess::TONE_BAD, ours.tone
    assert_equal Operator::Attention::TARGET_RUN, ours.target
    assert_equal failed.id, ours.target_id
    assert_match "Faraday::TimeoutError", ours.detail
    assert_equal Operator::IncidentProcess::TONE_WARN, tune.tone
  end

  test "a run whose last post never reached the thread needs a person, and one that did does not" do
    lost = run!(status: Investigation::STATUS_SUCCEEDED, thread_id: "1.2")
    posted = run!(status: Investigation::STATUS_SUCCEEDED, thread_id: "1.3", answer_posted_at: Time.current)

    assert item_for(Operator::Attention::KIND_HALON_NOT_POSTED, lost)
    assert_nil item_for(Operator::Attention::KIND_HALON_NOT_POSTED, posted)
  end

  test "repeats of one failed Slack call are one item, opening the incident whose channel it was in" do
    2.times do
      PlatformCallFailure.create!(workspace: @workspace, platform: Platforms::SLACK, operation: "chat.postMessage",
                                  error_class: "AdapterError::NotInChannel", channel_id: @incident.channel_id)
    end

    platform = items.select { |item| item.kind == Operator::Attention::KIND_PLATFORM_FAILED && item.target_id == @incident.id }

    assert_equal 1, platform.size
    assert_match "2 times", platform.sole.detail
  end

  test "a failed webhook delivery opens the incident it was about" do
    event = @incident.incident_events.create!(event_type: IncidentEvent::MILESTONE_NOTED, metadata: { statement: "x" })
    webhook = @workspace.webhooks.create!(name: "Acme", url: "https://hooks.acme.dev/in", subscribed_events: [ IncidentEvent::INCIDENT_CREATED ])
    WebhookDelivery.create!(webhook: webhook, incident_event: event, event_type: IncidentEvent::INCIDENT_CREATED,
                            signed_payload: "{}", state: :failed, attempts: 5, response_code: 502)

    hook = items.find { |item| item.key == "webhook-#{webhook.id}" }

    assert_equal @incident.id, hook.target_id
    assert_match "hooks.acme.dev", hook.subject
    assert_match "HTTP 502", hook.detail
  end

  test "a failed workflow opens its run" do
    workflow = SolidWorkflow::Workflow.create!(name: "incident.creation.v1", workflow_class: "IncidentCreationWorkflow", subject: @incident, state: "failed")
    workflow.steps.create!(name: "invite_responders", position: 0, status: "failed", attempts: 3, max_attempts: 3, last_error: "not_in_channel")

    item = items.find { |candidate| candidate.key == "workflow-#{workflow.id}" }

    assert_equal Operator::Attention::TARGET_WORKFLOW, item.target
    assert_match "invite_responders", item.subject
    assert_match "3 of 3 attempts used", item.detail
  end

  test "the queue is read across every workspace, and a queue that cannot be read adds nothing" do
    jobs = stub(backed_up: [ Operator::JobHealth::Queue.new(name: "investigations", waiting: 4, oldest_at: 5.minutes.ago) ], failed_kinds: [])

    everywhere = Operator::Attention.new(Operator::Filter.new, jobs: jobs).items
    one_workspace = Operator::Attention.new(Operator::Filter.new(workspace: @workspace), jobs: jobs).items

    assert everywhere.any? { |item| item.kind == Operator::Attention::KIND_QUEUE_BACKED_UP }
    assert one_workspace.none? { |item| item.kind == Operator::Attention::KIND_QUEUE_BACKED_UP }
    assert_nothing_raised { Operator::Attention.new(Operator::Filter.new, jobs: nil).items }
  end

  test "failures come before warnings" do
    run!(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT)
    run!(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    tones = items.map(&:tone)

    assert_equal tones.sort_by { |tone| tone == Operator::IncidentProcess::TONE_BAD ? 0 : 1 }, tones
  end

  test "a queue the test database does not have reads as nothing rather than failing the page" do
    assert_nil Operator::JobHealth.read(since: 1.day.ago)
  end

  private

  def items = Operator::Attention.new(Operator::Filter.new(workspace: @workspace), jobs: nil).items

  def item_for(kind, run) = items.find { |item| item.kind == kind && item.target_id == run.id }

  def run!(status:, **attributes)
    @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400,
      status: status, completed_at: Time.current, **attributes
    )
  end
end
