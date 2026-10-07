require "application_system_test_case"

# A code fix showed only a spinner on Fix code for minutes. Its coding agent's steps now show under it as they happen,
# and the step ends with what changed, the tests and the pull request, or with its last steps and why it stopped.
class AgentCodeFixProgressTest < ApplicationSystemTestCase
  include FixPlanTestHelper

  PHONE = [ 390, 844 ].freeze
  STEPS = [
    "Got acme/api ready at main", "Thinking: I'll start by reading the database config.", "Read config/database.yml",
    "Searched for 'pool' in *.yml files", "Looked for files matching 'test/**/*_test.rb'", "Thinking: The pool is 2, it should be 10.",
    "Edited config/database.yml", "Created test/pool_test.rb"
  ].freeze

  # The test adapter only records broadcasts, and this test needs the browser to receive them.
  setup do
    @cable = ActionCable.server.config.cable
    ActionCable.server.config.cable = { "adapter" => "async" }
    ActionCable.server.restart
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    ApplicationCable::Connection.any_instance.stubs(:signed_in_user).returns(users(:alice))
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(base_config: { "installation_id" => "1" })
    @tool = github.tools.create!(name: "fix_code", description: "Writes code", params_schema: {}, enabled: true, read_only: false)
    @arguments = { "repo" => "acme/api", "title" => "Restore the pool size", "brief" => "The pool went from 10 to 2" }
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "while the agent works, its newest steps, the time and the files so far show under the step, the earlier ones a click away" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Fix the pool size in acme/api")
    visit agent_chat_path(conversation)
    assert_text "Fix the pool size"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    step = Chat::Tools.step(@tool.model_facing_name, @arguments, workspace: @workspace)
    delivery.step(key: "call_1", step: step, status: :running)
    work = Chat::CodeFixProgress.start(at: 3.minutes.ago)
    work.live!
    STEPS.first(3).each { |line| work.add(line) }
    delivery.progress(key: "call_1", step: step, progress: work)
    assert_text "Read config/database.yml"
    travel 2.seconds do
      STEPS.drop(3).each { |line| work.add(line) }
      work.changed!("config/database.yml")
      work.changed!("test/pool_test.rb")
      work.add("Ran ruby test/pool_test.rb", result: Chat::CodeFixProgress::RESULT_PASSED)
      work.tested!("ruby test/pool_test.rb", passed: true)
      delivery.progress(key: "call_1", step: step, progress: work)
    end

    assert_text "Ran ruby test/pool_test.rb"
    assert_text "2 files changed: config/database.yml, test/pool_test.rb"
    assert_text(/3m \d+s so far/)
    assert_no_text "Got acme/api ready at main"
    shot("code-fix-running")

    click_button "Show 4 steps before these"
    assert_text "Got acme/api ready at main"
    shot("code-fix-running-all-steps")

    page.current_window.resize_to(*PHONE)
    assert_text "Ran ruby test/pool_test.rb"
    shot("code-fix-running-phone")
  end

  test "once it opened the pull request, the step sums up what changed, the tests and the link, also after a reload" do
    conversation = finished_chat do |work|
      work.add("Ran ruby test/pool_test.rb", result: Chat::CodeFixProgress::RESULT_FAILED)
      work.tested!("ruby test/pool_test.rb", passed: false)
      work.add("Edited config/database.yml")
      work.add("Ran ruby test/pool_test.rb", result: Chat::CodeFixProgress::RESULT_PASSED)
      work.tested!("ruby test/pool_test.rb", passed: true)
      work.opened!(files: { "config/database.yml" => [ 1, 1 ], "test/pool_test.rb" => [ 6, 0 ] }, pull_request: "https://github.com/acme/api/pull/7")
    end

    visit agent_chat_path(conversation)
    open_trace

    assert_text "Changed 2 files"
    assert_text "+6 -0"
    assert_text "ruby test/pool_test.rb"
    assert_link "Open the pull request", href: "https://github.com/acme/api/pull/7"
    assert_text(/Took 6m 0s · 11 steps/)
    shot("code-fix-opened")

    click_button "Show the steps"
    assert_text "Got acme/api ready at main"

    page.current_window.resize_to(*PHONE)
    click_button "Hide the steps"
    assert_link "Open the pull request"
    shot("code-fix-opened-phone")
  end

  test "when it stopped, its last steps and why show in place of a summary" do
    conversation = finished_chat(failed: true) do |work|
      work.add("Stopped: Budget spent", result: Chat::CodeFixProgress::RESULT_FAILED)
      work.failed!("The coding agent stopped with an error, so its change is not opened.")
    end

    visit agent_chat_path(conversation)
    open_trace

    assert_text "Stopped: Budget spent"
    assert_text "The coding agent stopped with an error, so its change is not opened."
    assert_no_link "Open the pull request"
    shot("code-fix-stopped")
  end

  test "a fix applied from a run shows the same on its code step" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    code = plan.steps.third
    code.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING, started_at: 2.minutes.ago)
    work = Chat::CodeFixProgress.start(at: 2.minutes.ago)
    work.live!
    STEPS.each { |line| work.add(line) }
    work.changed!("dns.tf")
    code.track!(work)
    investigation = plan.finding.investigation

    visit incident_path(investigation.incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      assert_text "Created test/pool_test.rb"
      assert_text "1 file changed: dns.tf"
      find("li", text: "Drop the rule from dns.tf").scroll_to(:center)
    end
    shot("code-fix-run-page-running")
  end

  private

  # A chat whose fix ended, saved as a reload reads it.
  def finished_chat(failed: false)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Fix the pool size in acme/api")
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @tool.model_facing_name, arguments: @arguments, failed: failed,
                                      failure_kind: (Chat::StepOutcome::FAILURE_ERROR if failed))
    chat.add_message(role: :tool, content: failed ? "The coding agent stopped with an error." : "Opened https://github.com/acme/api/pull/7", tool_call_id: "call_1")
    work = Chat::CodeFixProgress.start(at: 6.minutes.ago)
    work.live!
    STEPS.each { |line| work.add(line, at: 5.minutes.ago) }
    work.changed!("config/database.yml")
    yield work
    work.instance_variable_set(:@finished_at, Time.current)
    Chat::StepProgress.keep!(chat, "call_1", work)
    conversation.note!(failed ? "The coding agent ran out of budget before it finished." : "I opened https://github.com/acme/api/pull/7.")
    conversation.reply_delivered!
    conversation
  end

  # A trace that ended collapses, and one with a failed step stays open.
  def open_trace
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"
  end

  def open_stream(delivery)
    50.times do
      delivery.thinking!
      return if page.has_text?("Working", wait: 0.2)
    end

    flunk "the page never opened its socket"
  end

  def shot(name) = page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
end
