require "application_system_test_case"

class OperatorHalonTest < ApplicationSystemTestCase
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
    @incident = incidents(:active_critical_ws1)
    @run = answered_run
    @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400, status: Investigation::STATUS_FAILED,
      error_summary: "RubyLLM::OverloadedError", brief: { Investigation::Brief::KEY_SYMPTOM => "is billing down" },
      started_at: 2.hours.ago, completed_at: 2.hours.ago + 38.seconds, turns_used: 4, spent_micros: 210_000
    )
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "an operator goes from what needs attention to a run's health and then its trace, and reads one tool call" do
    visit operator_root_path
    assert_text "Needs attention"
    assert_text "Halon failed on our side"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-overview.png"))

    visit operator_halon_path
    assert_text "Runs by how they ended"
    assert_text "postgresql.current_activity"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-halon.png"))

    click_link "#{@incident.identifier} #{@incident.name}"
    assert_text(/selected span/i)
    click_button "postgresql_current_activity"
    assert_text "idle in transaction"
    assert_text "This is the customer's data."
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-trace.png"))
  end

  test "a chat from Slack reads as Slack shows it, and the operator can switch to what the model read" do
    bob = workspace_memberships(:bob_workspace_one)
    direct = Conversation.start_direct!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one), channel_id: "D0ALICE", thread_id: "1")
    direct.ask!("@#{bob.display_name} (#{bob.platform_user_id}) says checkout is 🔥", as_written: "<@#{bob.platform_user_id}> says checkout is :fire:")

    visit operator_halon_chat_path(direct)
    assert_text(/selected span/i)
    click_button "Asked"
    assert_selector "pre", exact_text: "@#{bob.display_name} says checkout is 🔥"

    find("#span-as-read").click
    assert_selector "pre", exact_text: "@#{bob.display_name} (#{bob.platform_user_id}) says checkout is 🔥"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-chat-as-read.png"))

    find("#span-as-read").click
    assert_selector "pre", exact_text: "@#{bob.display_name} says checkout is 🔥"
  end

  test "a span's content that arrives after the operator moved on never replaces the span they are reading" do
    slow = @run.steps.find_by!(position: 1)
    fast = @run.steps.find_by!(position: 2)
    answered = Queue.new
    Operator::RunTrace.any_instance.stubs(:body_for).with { |key, **_options| key == "tool-#{fast.id}" }.returns("the fast span's content")
    Operator::RunTrace.any_instance.stubs(:body_for).with do |key, **_options|
      next false unless key == "tool-#{slow.id}"

      sleep 1.5
      answered << true
      true
    end.returns("the slow span's content")

    visit operator_halon_run_path(@run, Operator::Trace::SPAN_PARAM => "tool-#{fast.id}")
    assert_selector "pre", exact_text: "the fast span's content"
    click_button "github_changes_before"
    click_button "postgresql_current_activity"
    assert_selector "pre", exact_text: "the fast span's content"

    Timeout.timeout(5) { answered.pop }
    assert_no_selector "pre", exact_text: "the slow span's content", wait: 2
    assert_selector "pre", exact_text: "the fast span's content"
  end

  test "an operator pastes an id into Find and lands on its trace, and an incident number lists every workspace's" do
    visit operator_root_path
    fill_in "operator-find", with: @run.id.first(8)
    find("#operator-find").send_keys(:enter)
    assert_text(/selected span/i)
    assert_current_path(/#{operator_halon_run_path(@run)}/)

    other = workspaces(:slack_workspace_two).incidents.find_by(identifier: @incident.identifier)
    fill_in "operator-find", with: @incident.identifier
    find("#operator-find").send_keys(:enter)
    if other
      assert_text "matches for"
      page.save_screenshot(Rails.root.join("tmp/screenshots/operator-find.png"))
    else
      assert_current_path(/#{operator_incident_path(@incident)}/)
    end
  end

  test "an operator opens a chat and reads each turn on its own clock" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.update!(title: "Why is checkout slow")
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :user, content: "Why is checkout slow?")
    chat.add_message(role: :assistant, content: "The 14:02 deploy halved the connection pool.")

    visit operator_halon_chats_path
    click_link "Why is checkout slow"
    assert_text(/turn 1/i)
    click_button "Replied"
    assert_text "halved the connection pool"
    page.save_screenshot(Rails.root.join("tmp/screenshots/operator-chat.png"))
  end

  private

  def answered_run
    started = 3.hours.ago
    run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED, started_at: started, completed_at: started + 131.seconds, attempts: 1,
      turns_used: 11, spent_micros: 1_320_000, thread_id: "1.2", answer_posted_at: started + 132.seconds,
      seed_pack: { "alerts" => [ {}, {}, {} ], "services" => [ {}, {} ], "gathered_at" => started.iso8601 }
    )
    6.times do |turn|
      Inference.create!(workspace: @workspace, feature: FirefightAi::Investigator::FEATURE, provider: "anthropic", model: "claude-sonnet-4-5",
                        status: Inference::STATUS_SUCCESS, inferable: run, input_tokens: 400, cache_read_tokens: 15_900 + (turn * 900),
                        output_tokens: 410, cost_micros: 60_000, latency_ms: 4200, created_at: started + ((turn * 20) + 8).seconds)
    end
    tool!(run, 1, "github_changes_before", "github.changes_before", started + 1.second, 6.8, "14 changes ranked")
    tool!(run, 2, "postgresql_current_activity", "postgresql.current_activity", started + 30.seconds, 0.6,
          "state | connections\nactive | 96\nidle in transaction | 4\nmax_connections | 100")
    run.record_hypothesis!(assertion: "A deploy changed the pool size").update_columns(created_at: started + 40.seconds)
    run.conclude!(summary: "The 14:02 deploy halved the connection pool").update_columns(created_at: started + 128.seconds)
    run
  end

  def tool!(run, position, name, action_key, at, seconds, result)
    invocation = Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, principal_label: "Firefight Investigator", action_key: action_key,
      idempotency_key: SecureRandom.uuid, decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS,
      duration_ms: (seconds * 1000).round, source: AbilityGateway::SOURCE_INVESTIGATION, created_at: at
    )
    run.steps.create!(position: position, tool_name: name, action_key: action_key, status: Investigation::Step::STATUS_SUCCEEDED,
                      invocation: invocation, started_at: at, completed_at: at + seconds, raw_result: result)
  end
end
