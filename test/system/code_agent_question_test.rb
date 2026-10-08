require "application_system_test_case"

# A coding agent writing a change asks the person a question under the running step, they answer it there, and the
# change carries on. Once it opens, the step shows what Halon's review found and what nobody could verify.
class CodeAgentQuestionTest < ApplicationSystemTestCase
  include FixPlanTestHelper

  PHONE = [ 390, 844 ].freeze

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
    @arguments = { "repo" => "acme/api", "title" => "Send the release tag", "brief" => "The release job sends the commit" }
  end

  teardown do
    ActionCable.server.config.cable = @cable
    ActionCable.server.restart
  end

  test "the person answers the agent's question under the running step, and sees who answered once it moves on" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    question = ask(conversation, "The workflow can send the tag name or the full ref. Which does the deploy webhook expect?")
    visit agent_chat_path(conversation)
    assert_text "Make the release job send the tag"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    step = Chat::Tools.step(@tool.model_facing_name, @arguments, workspace: @workspace)
    delivery.step(key: "call_1", step: step, status: :running)
    work = running_work
    work.add("Asked a question")
    work.asked!(question.to_h)
    delivery.progress(key: "call_1", step: step, progress: work)

    assert_text "The coding agent asks"
    assert_text "Which does the deploy webhook expect?"
    assert_text "Waiting for an answer"
    assert_text(/Expires in [45] minutes\. If nobody answers by then, the change stops\./)
    shot("code-question-open")

    page.current_window.resize_to(*PHONE)
    assert_button "Send answer", disabled: true
    shot("code-question-open-phone")
    page.current_window.resize_to(1280, 900)

    fill_in "Your answer", with: "The tag name, such as v1.4.0."
    click_button "Send answer"
    assert_text "Your answer was sent to the coding agent."
    assert_equal [ CodeAgentQuestion::STATUS_ANSWERED, "The tag name, such as v1.4.0." ], question.reload.values_at(:status, :answer)

    travel 2.seconds do
      work.asked!(question.to_h)
      work.add("Edited .github/workflows/release.yml")
      delivery.progress(key: "call_1", step: step, progress: work)
    end
    assert_text "Alice Smith answered: The tag name, such as v1.4.0."
    assert_no_button "Send answer"
    assert_no_text "Waiting for an answer"
    shot("code-question-answered")
  end

  test "once it opened, the step leads with Halon's review, what nobody verified, and the checks that ran" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @tool.model_facing_name, arguments: @arguments)
    chat.add_message(role: :tool, content: "Opened https://github.com/acme/api/pull/7", tool_call_id: "call_1")
    work = running_work
    work.checked!([ Integrations::CodeChecks::Check.new(name: "actionlint .github/workflows/release.yml", status: Integrations::CodeChecks::PASSED, output: ""),
                    Integrations::CodeChecks::Check.new(name: "yaml .github/workflows/release.yml", status: Integrations::CodeChecks::PASSED, output: "") ])
    work.reviewed!({ "ran" => true, "right" => true, "findings" => [ "No test covers the release job." ],
                     "unverified" => [ "That the deploy webhook reads the tag from the ref field, which its docs did not say." ],
                     "summary" => "Sends the tag", "sentBack" => true })
    work.opened!(files: { ".github/workflows/release.yml" => [ 3, 1 ] }, pull_request: "https://github.com/acme/api/pull/7")
    Chat::StepProgress.keep!(chat, "call_1", work)
    conversation.note!("I opened https://github.com/acme/api/pull/7.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"

    assert_text "Halon's review sent it back once, and the corrected change does what was asked"
    assert_text "No test covers the release job."
    assert_text "Not verified, so check before merging"
    assert_text "That the deploy webhook reads the tag from the ref field"
    assert_text "actionlint .github/workflows/release.yml"
    assert_link "Open the pull request", href: "https://github.com/acme/api/pull/7"
    shot("code-fix-reviewed")
  end

  test "on a run's fix step the question shows too, and someone the change does not run as is told who can answer" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: workspace_memberships(:bob_workspace_one), from: AbilityGateway::SOURCE_WEB)
    code = plan.steps.third
    code.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING, started_at: 2.minutes.ago)
    request = code.code_agent_request(workspace_memberships(:bob_workspace_one))
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/infra", request: request)
    question = CodeAgentQuestion.ask!(session, "Should the rule go from dns.tf only, or from the staging copy too?")
    work = running_work
    work.asked!(question.to_h)
    code.track!(work)
    investigation = plan.finding.investigation

    visit incident_path(investigation.incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      assert_text "Should the rule go from dns.tf only"
      assert_text "Only Bob Jones can answer, since the change runs as them."
      assert_no_button "Send answer"
      find("li", text: "Drop the rule from dns.tf").scroll_to(:center)
    end
    shot("code-question-run-page")
  end

  private

  def ask(conversation, text)
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    CodeAgentQuestion.ask!(session, text)
  end

  def running_work
    work = Chat::CodeFixProgress.start(at: 3.minutes.ago)
    work.live!
    [ "Got acme/api ready at main", "Read with fake_list_deploy_hooks", "Read .github/workflows/release.yml" ].each { |line| work.add(line) }
    work
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
