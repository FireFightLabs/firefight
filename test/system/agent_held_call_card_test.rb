require "application_system_test_case"

# A call an approval rule held in a chat. The card says what Halon wants to do and who may approve it, follows the run as
# a checklist once approved, and says how it went. A call approved before approving ran it still asks to be run.
class AgentHeldCallCardTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include FixPlanTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    WorkspaceAdapter.stubs(:for).returns(stub_everything)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    faylee.integration_environments.create!(credentials: { token: "x" }.to_json).store_fields!("project" => "faylee")
    @tool = faylee.tools.create!(name: "api_request", description: "API", read_only: false, enabled: true, params_schema: { "type" => "object" })
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @conversation.ask!("Scale Faylee's web service to zero")
    @chat = @conversation.chat
    asked = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = asked.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "faylee_api_request", arguments: { "method" => "POST", "path" => "services/web/scale" })
    said = @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: Chat::Tools.waiting_for_approval(@tool.action_key, held: true))
    call.update_columns(result_id: said.id)
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "Scaling web to zero needs Bob's approval. I will ask you to run it once he approves.")
    @conversation.reply_delivered!
  end

  test "an approved call asks to be run under how things stand now, counts down its hour, and runs only when Run is pressed" do
    held = held_call(status: Chat::HeldCall::STATUS_READY, state: "web already runs 0 instances, since 14:02.", change: Chat::CurrentState::DONE_ALREADY)

    visit agent_chat_path(@conversation)

    assert_text "Halon wants to: api request on Faylee (Northflank), project faylee"
    assert_text "Approved by Bob Jones. Run it now?"
    assert_text "This looks done already."
    assert_text "web already runs 0 instances, since 14:02."
    assert_text "Expires in 52 minutes"
    assert_no_text "services/web/scale"
    click_button "Details"
    assert_text "services/web/scale"
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_ready.png").to_s)
    assert_equal Chat::HeldCall::STATUS_READY, held.reload.status, "nothing ran on approval"

    click_button "Run"

    assert_toast "Running it now."
    assert_equal [ Chat::HeldCall::STATUS_RUNNING, @alice ], [ held.reload.status, held.decided_by ]
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @alice.id, held.id ])
  end

  test "while Halon checks Run waits, and an expired approval offers Ask again" do
    checking = held_call(status: Chat::HeldCall::STATUS_CHECKING)

    visit agent_chat_path(@conversation)

    assert_text "Halon is checking how things stand now. Run waits until it has."
    assert_button "Run", disabled: true
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_checking.png").to_s)

    checking.update_columns(status: Chat::HeldCall::STATUS_EXPIRED)
    checking.approval.update_columns(status: Ability::Approval::STATUS_EXPIRED)
    visit agent_chat_path(@conversation)

    assert_text "Expired: api request on Faylee (Northflank), project faylee"
    assert_text "The approval expired before it ran. Ask for it again if it is still needed."
    assert_button "Ask again"
    assert_no_button "Run"
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_expired.png").to_s)
  end

  test "a denial says who denied it and that nothing ran" do
    held_call(status: Chat::HeldCall::STATUS_DENIED, approval_status: Ability::Approval::STATUS_DENIED)

    visit agent_chat_path(@conversation)

    assert_text "Denied: api request on Faylee (Northflank), project faylee"
    assert_text "Denied by Bob Jones. Nothing ran."
    assert_no_button "Run"
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_denied.png").to_s)
  end

  test "while it waits it says who may approve it, and once approved it follows the change as a checklist and ends on its link" do
    held = held_call(status: Chat::HeldCall::STATUS_WAITING, approval_status: Ability::Approval::STATUS_PENDING)

    visit agent_chat_path(@conversation)

    assert_text "Halon wants to: api request on Faylee (Northflank), project faylee"
    assert_text "Waiting for a workspace admin to approve it."
    assert_no_button "Run"
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_waiting.png").to_s)

    held.approval.update_columns(status: Ability::Approval::STATUS_APPROVED, approver_type: @bob.class.polymorphic_name, approver_id: @bob.id)
    held.update_columns(status: Chat::HeldCall::STATUS_RUNNING, decided_by_id: @bob.id)
    work = Chat::CodeFixProgress.start
    work.changed!("app/a.rb")
    Chat::StepProgress.keep!(@chat, "call_1", work)
    visit agent_chat_path(@conversation)

    assert_text "Approved by Bob Jones, working on it."
    assert_text "Write the change"
    assert_text "1 file changed"
    assert_text "Check the change"
    assert_text "Open a pull request"
    page.save_screenshot(Rails.root.join("tmp/screenshots/held_call_running.png").to_s)

    work.opened!(files: { "app/a.rb" => [ 1, 1 ] }, pull_request: "https://github.com/acme/shop/pull/856")
    Chat::StepProgress.keep!(@chat, "call_1", work)
    held.update_columns(status: Chat::HeldCall::STATUS_RAN)
    visit agent_chat_path(@conversation)

    assert_text "Done: api request on Faylee (Northflank), project faylee"
    assert_link "github.com/acme/shop/pull/856", href: "https://github.com/acme/shop/pull/856"
  end

  test "an approved step of a fix asks to be run on the run page, under how things stand now" do
    plan = build_fix_plan(@workspace)
    plan.apply!(by: @alice, from: AbilityGateway::SOURCE_WEB)
    approval = @workspace.ability_approvals.create!(principal: @alice, principal_label: "user:Alice Smith", action_key: "cloudflare.execute",
                                                    request_digest: "d", required_role: "admin", status: Ability::Approval::STATUS_APPROVED,
                                                    approver: @bob, held_for_run: true, run_expires_at: 51.5.minutes.from_now)
    step = plan.steps.first
    step.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id, checked_state: "The rule still blocks /checkout.",
                        state_change: Chat::CurrentState::UNCHANGED, state_checked_at: Time.current)

    visit investigation_path(plan.finding.investigation)

    assert_text "Bob Jones approved it. Run this step?"
    assert_text "The rule still blocks /checkout."
    assert_text "Expires in 52 minutes"
    find("button", text: "Run", exact_text: true).scroll_to(:center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/fix_step_approved.png").to_s)
    find("button", text: "Run", exact_text: true).click

    assert_toast "Running the step now."
    assert_equal Investigation::RemediationStep::STATUS_RUNNING, step.reload.status
  end

  private

  def held_call(status:, state: nil, change: nil, approval_status: Ability::Approval::STATUS_APPROVED)
    approval = @workspace.ability_approvals.create!(
      principal: @alice, principal_label: "user:Alice Smith", action_key: @tool.action_key, request_digest: "d", required_role: "admin",
      params: { "method" => "POST", "path" => "services/web/scale" }, status: approval_status, approver: @bob, held_for_run: true,
      run_expires_at: (51.5.minutes.from_now if approval_status == Ability::Approval::STATUS_APPROVED), resolved_at: Time.current
    )
    Chat::HeldCall.create!(chat: @chat, approval: approval, tool_name: "faylee_api_request", target: "Faylee (Northflank), project faylee",
                           tool_call_id: "call_1", status: status, checked_state: state, state_change: change,
                           state_checked_at: (Time.current if change))
  end
end
