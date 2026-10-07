require "application_system_test_case"

# Seen in a real chat: Halon checked whether ember-landing was a Cloudflare Pages project, Cloudflare answered that it
# is not, and the step showed a red cross with nothing but its arguments under it. An opened step now says what came back.
class AgentStepOutcomesTest < ApplicationSystemTestCase
  PAGES_INTENT = "Check whether ember-landing is a Cloudflare Pages project and read its current configuration before renaming it".freeze
  WORKERS_INTENT = "List Cloudflare Workers in the account to identify ember-landing and determine whether it can be renamed safely".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "an opened step shows its whole sentence and what came back, a not found quietly and a failure in red" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    conversation.ask!("Rename ember-landing to ember-site")
    chat = conversation.chat
    reply = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    called!(chat, reply, "call_1", PAGES_INTENT, "/pages/projects/ember-landing",
            "Error: Cloudflare API error: 8000007: Project not found. The specified project name does not match any of your existing projects.",
            failure: Chat::StepOutcome::FAILURE_NOT_FOUND)
    called!(chat, reply, "call_2", WORKERS_INTENT, "/workers/scripts",
            "{\n  \"result\": [\n    {\n      \"id\": \"ember-landing\",\n      \"has_assets\": true,\n      \"handlers\": [\"fetch\"]\n    }\n  ]\n}\n" \
            "Open this in Cloudflare, and give the person this link with what you found: https://dash.cloudflare.com/acc/workers/services/view/ember-landing")
    called!(chat, reply, "call_3", "Read the Worker's routes to see which hostnames reach ember-landing", "/workers/scripts/ember-landing/routes",
            "Error: Cloudflare API error: 10000: Authentication error", failure: Chat::StepOutcome::FAILURE_ERROR)
    conversation.note!("ember-landing is a Worker, not a Pages project, so renaming it means a new Worker and moving its routes.")
    conversation.reply_delivered!

    visit agent_chat_path(conversation)
    # A failed step holds the trace open, so it is opened only when nothing did.
    trace = find("button[aria-expanded]", text: /Worked for/)
    trace.click if trace["aria-expanded"] == "false"
    find("button", text: PAGES_INTENT).click
    find("button", text: WORKERS_INTENT).click
    find("button", text: "Read the Worker's routes").click

    assert_text PAGES_INTENT
    assert_text "Not found. Cloudflare API error: 8000007: Project not found. The specified project name does not match any of your existing projects."
    assert_text "Returned 9 lines, 260 characters"
    assert_text '{"result":[{"id":"ember-landing","has_assets":true,"handlers":["fetch"]}]}'
    assert_link "Open in Cloudflare", href: "https://dash.cloudflare.com/acc/workers/services/view/ember-landing"
    assert_text "Failed. Cloudflare API error: 10000: Authentication error"
    assert_selector ".sr-only", text: "Not found", visible: :all
    page.save_screenshot(Rails.root.join("tmp/screenshots/agent-step-outcomes.png"))
  end

  test "a run's story shows each step's outcome, a not found as an answer and an error in red" do
    incident = incidents(:active_critical_ws1)
    investigation = @workspace.investigations.create!(
      subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, started_at: 60.seconds.ago, completed_at: Time.current,
      brief: { Investigation::Brief::KEY_SYMPTOM => "ember.dev answers 404 since 14:02" }
    )
    investigation.note_started!
    step!(investigation, 1, "Execute · Cloudflare Pages project ember-landing").fail!(
      "NotFound: Cloudflare answered 404: Project not found", kind: Chat::StepOutcome::FAILURE_NOT_FOUND
    )
    step!(investigation, 2, "Execute · Cloudflare Workers").succeed!(
      compacted_result: "ember-landing\nember-api",
      raw_result: "ember-landing\nember-api\nOpen this in Cloudflare, and give the person this link with what you found: https://dash.cloudflare.com/acc/workers"
    )
    step!(investigation, 3, "Execute · Cloudflare routes of ember-landing").succeed!(
      compacted_result: "Error: Cloudflare API error: 10000: Authentication error", failure_kind: Chat::StepOutcome::FAILURE_ERROR
    )
    investigation.note_answered!(investigation.conclude!(summary: "ember-landing is a Worker whose route was removed at 14:02."))

    visit incident_path(incident, Investigation::QUERY_PARAM => investigation.id)

    within("[role=dialog]") do
      assert_text "Not found. Cloudflare answered 404: Project not found"
      assert_text "Returned 2 lines, 139 characters"
      assert_link "Open in Cloudflare", href: "https://dash.cloudflare.com/acc/workers"
      assert_text "Failed. Cloudflare API error: 10000: Authentication error"
      find("li#step-1").scroll_to(:center)
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-step-outcomes.png"))
  end

  private

  def called!(chat, reply, id, intent, path, said, failure: nil)
    code = "async () => { return await cloudflare.request({method:'GET', path:'/accounts/'+accountId+'#{path}'}); }"
    reply.ruby_llm_tool_calls.create!(tool_call_id: id, name: "cloudflare_execute",
                                      arguments: { "code" => code, "intent" => intent, "account_id" => "a9baf736efd9" },
                                      failed: failure.present?, failure_kind: failure)
    chat.add_message(role: :tool, content: FirefightAi::Evidence.frame("cloudflare_execute", said), tool_call_id: id)
  end

  def step!(investigation, position, label)
    investigation.steps.create!(position: position, tool_name: "cloudflare_execute", label: label, action_key: "cloudflare.execute",
                                status: Investigation::Step::STATUS_RUNNING, started_at: (60 - (position * 10)).seconds.ago)
  end
end
