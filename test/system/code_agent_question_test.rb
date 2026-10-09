require "application_system_test_case"

# A coding agent writing a change asks the person a question under the running step, they answer it there, and the
# change carries on. Once it opens, the step shows what Halon's review found and what nobody could verify.
class CodeAgentQuestionTest < ApplicationSystemTestCase
  include FixPlanTestHelper
  include CodeQuestionTestHelper

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

  test "the person picks one of the agent's options in a click under the running step, and sees what they chose once it moves on" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    question = ask(conversation, "Today the release workflow tells Northflank to start a run named after the commit. When you tag v1.4.0, " \
                                 "what should the Northflank run be called?")
    visit agent_chat_path(conversation)
    assert_text "Make the release job send the tag"

    delivery = Conversation::LiveDelivery.new(conversation)
    open_stream(delivery)
    step = Chat::Tools.step(@tool.model_facing_name, @arguments, workspace: @workspace)
    delivery.step(key: "call_1", step: step, status: :running)
    work = running_work
    work.add("Asked a question")
    3.times { |seconds| travel(seconds * 40) { work.waited!(question.created_at) } }
    work.asked!(question.to_h)
    delivery.progress(key: "call_1", step: step, progress: work)

    assert_text "The coding agent asks"
    assert_text "what should the Northflank run be called?"
    recommended = find("button", text: "Send the tag")
    assert_match(/Send the tag\s*Recommended\s*Northflank names the run after the release, such as v1\.4\.0\.\s*The release workflow already names its runs after the tag\./,
                 recommended.text)
    assert_match "Northflank names the run after the commit", find("button", text: "Send the commit").text
    assert_text(/Expires in [45] minutes\. If nobody answers by then, the change goes with the recommendation\./)
    assert_equal 1, all("li", text: "Waiting for your answer").size, "waits in a row are one line"
    shot("code-question-open")

    page.current_window.resize_to(*PHONE)
    assert_button "Send answer", disabled: true
    shot("code-question-open-phone")
    page.current_window.resize_to(1280, 900)

    recommended.click
    assert_text "Your answer was sent to the coding agent."
    assert_equal [ CodeAgentQuestion::STATUS_ANSWERED, 0 ], question.reload.values_at(:status, :chosen)

    travel 2.seconds do
      work.asked!(question.to_h)
      work.add("Edited .github/workflows/release.yml")
      delivery.progress(key: "call_1", step: step, progress: work)
    end
    assert_text "Alice Smith chose: Send the tag"
    assert_no_button "Send answer"
    assert_no_selector "button", text: "Send the commit"
    assert_no_text "Waiting for an answer"
    shot("code-question-answered")
    page.current_window.resize_to(*PHONE)
    shot("code-question-answered-phone")
  end

  test "an answer Halon gave keeps Change answer while the change runs, and the person picks another option and sees what it changed to" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    question = ask(conversation, "Today the release workflow tells Northflank to start a run named after the commit. When you tag v1.4.0, " \
                                 "what should the Northflank run be called?")
    question.answer_as_halon!("You asked for the tag in your first message.", option: 0)
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @tool.model_facing_name, arguments: @arguments)
    work = running_work
    work.asked!(question.to_h)
    work.add("Edited .github/workflows/release.yml")
    Chat::StepProgress.keep!(chat, "call_1", work)

    visit agent_chat_path(conversation)
    trace = find("button[aria-expanded]", text: /Working|Worked for/)
    trace.click if trace["aria-expanded"] == "false"

    assert_text "Halon chose: Send the tag"
    assert_no_selector "button", text: "Send the commit"
    find("button", text: "Change answer").scroll_to(:center)
    shot("code-question-change-offered")

    click_button "Change answer"
    assert_button "Submit", disabled: true
    find("button", text: "Send the tag").click
    assert_button "Submit", disabled: true
    find("button", text: "Send the commit").click
    assert_selector "button[aria-pressed=true]", text: "Send the commit"
    assert_button "Submit", disabled: false
    fill_in "Or write your own answer", with: "Send both"
    assert_no_selector "button[aria-pressed=true]"
    fill_in "Or write your own answer", with: ""
    find("button", text: "Send the commit").click
    find("button", text: "Submit").scroll_to(:center)
    shot("code-question-changing")

    click_button "Submit"
    assert_text "Your new answer was sent to the coding agent."
    assert_text "Changed to Send the commit by Alice Smith"
    assert_text "Halon chose: Send the tag"
    assert_no_button "Submit"
    assert_button "Change answer"
    assert_equal [ 1, @member ], question.reload.values_at(:changed_chosen, :changed_by)
    assert_equal 1, CodeAgentQuestion.correction_waiting.where(id: question.id).count
    find("button", text: "Change answer").scroll_to(:center)
    shot("code-question-changed")

    question.session.close!
    visit agent_chat_path(conversation)
    trace = find("button[aria-expanded]", text: /Working|Worked for/)
    trace.click if trace["aria-expanded"] == "false"
    assert_text "Changed to Send the commit by Alice Smith"
    assert_no_button "Change answer"
  end

  test "on a run's fix step the person the change runs as changes a settled answer in their own words" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: @member, from: AbilityGateway::SOURCE_WEB)
    code = plan.steps.third
    code.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING, started_at: 2.minutes.ago)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/infra", request: code.code_agent_request(@member))
    question = ask_question!(session, "Should the rule go from dns.tf only, or from the staging copy too?")
    question.update_columns(answer_due_at: 1.minute.ago)
    question.expire_if_overdue!
    work = running_work
    work.asked!(question.reload.to_h)
    code.track!(work)
    investigation = plan.finding.investigation

    visit incident_path(investigation.incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      assert_text "Nobody answered in time, so the change went with the recommendation."
      click_button "Change answer"
      fill_in "Or write your own answer", with: "From dns.tf only, and leave staging alone."
      click_button "Submit"
    end
    assert_text "Your new answer was sent to the coding agent."
    within("[role=dialog]") do
      assert_text "Changed to From dns.tf only, and leave staging alone. by Alice Smith"
    end
    assert_equal "From dns.tf only, and leave staging alone.", question.reload.changed_answer
  end

  test "once it opened, the step leads with Halon's review, what it verified, what is open, and the checks that ran or could not run" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @tool.model_facing_name, arguments: @arguments)
    chat.add_message(role: :tool, content: "Opened https://github.com/acme/api/pull/7", tool_call_id: "call_1")
    work = running_work
    work.checked!([ Integrations::CodeChecks::Check.new(name: "actionlint .github/workflows/release.yml", status: Integrations::CodeChecks::PASSED, output: ""),
                    Integrations::CodeChecks::Check.new(name: "yaml .github/workflows/release.yml", status: Integrations::CodeChecks::PASSED, output: ""),
                    Integrations::CodeChecks::Check.new(name: "bin/rails test test/jobs/release_test.rb", status: Integrations::CodeChecks::COULD_NOT_RUN,
                                                        output: "PG::ConnectionBad", reason: "no database was available") ])
    work.reviewed!({ "ran" => true, "right" => true, "findings" => [ "No test covers the release job." ],
                     "verified" => [ "The run name holds only letters, digits and hyphens, which Northflank's error message says it allows." ],
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
    assert_text "Verified"
    assert_text "which Northflank's error message says it allows"
    assert_text "Open questions"
    assert_text "That the deploy webhook reads the tag from the ref field"
    assert_text "actionlint .github/workflows/release.yml"
    assert_text "Could not run here, since no database was available."
    assert_link "Open the pull request", href: "https://github.com/acme/api/pull/7"
    shot("code-fix-reviewed")
  end

  test "a change that reached its spending limit asks to continue under its step, and the person continues it in a click" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Make the release job send the tag")
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    reply.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @tool.model_facing_name, arguments: @arguments)
    chat.add_message(role: :tool, content: "The code change reached its spending limit before finishing, so it is paused.", tool_call_id: "call_1")
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    pause = CodeAgentSession::Pause.create!(
      session: session, workspace: @workspace, conversation: conversation, arguments: @arguments, repository: "acme/api", base: "main",
      saved_branch: "halon/fix-1a2b3c4d", saved_commit: "s" * 40, copy_ref: "c" * 40, budget_micros: 2_000_000, resumable_until: 15.minutes.from_now
    )
    work = running_work
    work.paused!(pause.to_h)
    Chat::StepProgress.keep!(chat, "call_1", work)
    conversation.note!("It reached its spending limit, so I paused it. Continue or Stop it under the step.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"

    assert_text "This fix has reached its spending limit before finishing. Continue?"
    assert_text "Its work so far is saved on halon/fix-1a2b3c4d."
    assert_no_text "$"
    shot("code-fix-paused")
    page.current_window.resize_to(*PHONE)
    find("button", text: "Continue").scroll_to(:center)
    shot("code-fix-paused-phone")
    page.current_window.resize_to(1280, 900)

    click_button "Stop"
    within(find("[role='dialog']", text: "Stop this fix?")) do
      assert_text "The work saved so far is deleted."
      shot("code-fix-stop-confirm")
      click_button "Cancel"
    end
    assert pause.reload.offered?, "Stop asks first, so cancelling leaves the choice open"

    click_button "Continue"
    assert_text "The change carries on."
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"
    assert_text "Alice Smith chose Continue."
    assert_no_button "Stop"
    assert pause.reload.continuing?
    shot("code-fix-continued")
  end

  test "on a run's fix step the question shows too, and someone the change does not run as is told who can answer" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: workspace_memberships(:bob_workspace_one), from: AbilityGateway::SOURCE_WEB)
    code = plan.steps.third
    code.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING, started_at: 2.minutes.ago)
    request = code.code_agent_request(workspace_memberships(:bob_workspace_one))
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/infra", request: request)
    question = ask_question!(session, "Should the rule go from dns.tf only, or from the staging copy too?")
    work = running_work
    work.asked!(question.to_h)
    code.track!(work)
    investigation = plan.finding.investigation

    visit incident_path(investigation.incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      assert_text "Should the rule go from dns.tf only"
      assert_text "Only Bob Jones can answer, since the change runs as them."
      assert_no_button "Send answer"
      assert_text "Send the tag"
      assert_no_selector "button", text: "Send the tag"
      find("li", text: "Drop the rule from dns.tf").scroll_to(:center)
    end
    shot("code-question-run-page")
  end

  test "on a run's fix step someone the change does not run as sees Change answer disabled, with who can answer" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: workspace_memberships(:bob_workspace_one), from: AbilityGateway::SOURCE_WEB)
    code = plan.steps.third
    code.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING, started_at: 2.minutes.ago)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/infra", request: code.code_agent_request(workspace_memberships(:bob_workspace_one)))
    question = ask_question!(session, "Should the rule go from dns.tf only, or from the staging copy too?")
    question.answer_as_halon!("From dns.tf only, as Bob said.", option: 0)
    work = running_work
    work.asked!(question.reload.to_h)
    code.track!(work)
    investigation = plan.finding.investigation

    visit incident_path(investigation.incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      button = find("button", text: "Change answer")
      assert button.disabled?
      button.find(:xpath, "..").hover
    end
    assert_selector "[role='tooltip']", text: "Only Bob Jones can answer, since the change runs as them."
    shot("code-question-change-disabled")
  end

  private

  def ask(conversation, text)
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    ask_question!(session, text)
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
