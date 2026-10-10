require "test_helper"

# Alice asks Halon to cancel a GitHub Actions run Bob started. Bob is asked in his direct messages once Alice confirms,
# and the run is cancelled only once he agrees.
class Conversation::OwnerAsksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ARGUMENTS = { "repo" => "acme/shop", "run_id" => 123 }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @cancel = github.tools.create!(name: "cancel_workflow", description: "Cancel a run", enabled: true, read_only: false,
                                   params_schema: { "type" => "object", "properties" => { "repo" => {}, "run_id" => {} } })
    Integrations::GithubApp.stubs(:installation_token).returns("ghs_token")
    started_by("bob-gh", email: "bob@example.com")
    Slack::WorkspaceAdapter.any_instance.stubs(:post_owner_ask).returns({ channel_id: "D2", message_id: "2.1" })
    Slack::WorkspaceAdapter.any_instance.stubs(:update_owner_ask).returns({ success: true })
  end

  test "cancelling a run is a stop, read from the registry, and GitHub says who started it" do
    assert @cancel.reload.ability_action.effect?(Ability::Action::EFFECT_STOPS)

    owner = Integrations::NativePack.fetch!(@cancel.integration).owner_of("cancel_workflow", environment_row: @cancel.integration.integration_environments.first,
                                                                                             arguments: ARGUMENTS)

    assert_equal "bob-gh", owner.name
    assert_equal @bob, owner.member_in(@workspace)
    assert_equal "Deploy run 9 (123) in acme/shop", owner.what
  end

  test "a run a bot started has nobody to ask" do
    started_by("dependabot[bot]")

    assert_nil Integrations::NativePack.fetch!(@cancel.integration).owner_of("cancel_workflow", environment_row: @cancel.integration.integration_environments.first,
                                                                                                arguments: ARGUMENTS)
  end

  test "the owner is read before anyone is asked, named on the confirmation, and the call pauses even when allowed for the chat" do
    @chat.allow_tool!(@cancel.model_facing_name)
    @conversation.chat.reload

    assert tool.requires_approval?
    assert_nil tool.approval_resolver.call(cancel_call)
    ask = Chat::OwnerAsk.for_call(@chat, "call_1")

    assert_equal Chat::OwnerAsk::STATUS_PENDING, ask.status
    assert_equal @bob, ask.owner
    assert_includes Chat::Tools.confirmation(pause!).safeguards, [ "Started by", "Bob Jones, who is asked to agree once you confirm, before it runs." ]
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: @cancel.action_key, principal_id: @alice.id), "reading the owner is in the activity log"
  end

  test "a run the person started themselves, or one whose provider says nobody, runs as it would have" do
    started_by("alice-gh", email: "alice@example.com")
    @chat.allow_tool!(@cancel.model_facing_name)
    @conversation.chat.reload

    assert_equal true, tool.approval_resolver.call(cancel_call)
    assert_nil Chat::OwnerAsk.for_call(@chat, "call_1")
  end

  test "a stop a scheduled plan approved ahead still asks the owner at once, and their yes carries the plan on as approved" do
    plan = Chat::Plan.make!(chat: @chat, made_by: @alice, goal: "Stop the bad deploy", steps: [
      { "kind" => "change", "description" => "Cancel the deploy run", "tool" => @cancel.model_facing_name, "undo" => "Run the deploy again" },
      { "kind" => "check", "description" => "Check checkout against normal" }
    ])
    plan.update_columns(run_at: 1.minute.ago, approved_by_id: @alice.id, approved_at: 1.hour.ago)
    turn = Conversation::Turn.new(@conversation, asker: @alice, approved_plan: plan.reload)
    tool = Chat::Tools::Connection.new(turn, @cancel)

    assert_nil tool.approval_resolver.call(cancel_call), "the call pauses for the owner"
    assert_enqueued_with(job: OwnerAskJob) { Chat::Safeguards.prepare!(turn, [ pause! ]) }
    ask = Chat::OwnerAsk.for_call(@chat, "call_1")
    assert_equal Chat::OwnerAsk::STATUS_ASKED, ask.status
    assert_equal plan, ask.plan
    assert_equal Chat::APPROVAL_OWNER_ASKED, @chat.tool_calls.find_by!(tool_call_id: "call_1").approval

    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @alice.id, nil, nil, nil, nil, plan.id, Conversation::Plans::MOVE_RUN ]) do
      assert_nil Conversation::OwnerAsks.answer!(ask, agreed: true, by: @bob)
    end
    resumed = Conversation::Runner.new(@conversation, asker: @alice, plan: plan, plan_move: Conversation::Plans::MOVE_RUN).instance_variable_get(:@turn)
    assert resumed.approved_ahead?(@cancel.model_facing_name), "the resumed turn has the plan's approved tools, as the scheduled run had them"
  end

  test "an owner Firefight cannot match to a member is named for the person to check with" do
    started_by("stranger-gh")

    tool.approval_resolver.call(cancel_call)

    ask = Chat::OwnerAsk.for_call(@chat, "call_1")
    assert_equal Chat::OwnerAsk::STATUS_UNREACHABLE, ask.status
    assert_equal [ "Started by", "stranger-gh, who Firefight cannot ask here. Check with them before you confirm." ], ask.confirmation_row
  end

  test "confirming asks the owner and the turn waits for them, then goes on as the person who confirmed once they agree" do
    tool.approval_resolver.call(cancel_call)
    pause!

    assert_no_enqueued_jobs(only: ConversationReplyJob) do
      assert_enqueued_with(job: OwnerAskJob) { Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true } ], by: @alice) }
    end
    ask = Chat::OwnerAsk.for_call(@chat, "call_1")
    assert_equal Chat::OwnerAsk::STATUS_ASKED, ask.status
    assert_equal Chat::APPROVAL_OWNER_ASKED, @chat.tool_calls.find_by!(tool_call_id: "call_1").approval
    assert_equal :owner_asked, Chat::Tools.confirmation(@chat.tool_calls.find_by!(tool_call_id: "call_1")).status

    Slack::WorkspaceAdapter.any_instance.expects(:post_owner_ask).with { |user_id:, ask:| user_id == @bob.platform_user_id && ask.headline.include?("Alice Smith asked Halon to cancel workflow") }
                           .returns({ channel_id: "D2", message_id: "2.1" })
    OwnerAskJob.perform_now(ask.id)

    assert_equal "Only Bob Jones can answer this, since they started it.", Conversation::OwnerAsks.answer!(ask.reload, agreed: true, by: @alice)
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @alice.id ]) do
      assert_nil Conversation::OwnerAsks.answer!(ask, agreed: true, by: @bob)
    end
    assert_equal Chat::APPROVAL_APPROVED, @chat.tool_calls.find_by!(tool_call_id: "call_1").approval
  end

  test "an owner's no reaches Halon as the call's refusal, and nothing is cancelled" do
    tool.approval_resolver.call(cancel_call)
    pause!
    Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true } ], by: @alice)
    Integrations::NativeExecutor.expects(:call).never

    Interactions::OwnerAskHandler.execute(Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
                                                          user_id: @bob.platform_user_id, action_id: Identifiers::OWNER_DECLINE,
                                                          action_value: Chat::OwnerAsk.for_call(@chat, "call_1").id, channel_id: "D2", message_id: "2.1"))
    said = tool.call(tool_call: cancel_call, **ARGUMENTS.symbolize_keys)

    assert_match "Not run. Bob Jones, who started Deploy run 9 (123) in acme/shop, did not agree to it.", said
    assert @chat.tool_calls.find_by!(tool_call_id: "call_1").failed
  end

  test "moving on while the owner is asked withdraws the call and tells the owner it is no longer needed" do
    tool.approval_resolver.call(cancel_call)
    pause!
    Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true } ], by: @alice)
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "Never mind, what is broken?")

    closed = @chat.close_unfinished_calls!
    Conversation::OwnerAsks.withdraw!(@chat, closed.map(&:tool_call_id))

    assert_equal Chat::APPROVAL_WITHDRAWN, closed.sole.approval
    assert_equal Chat::UnfinishedCalls::NOT_AGREED, closed.sole.result.content
    assert_equal Chat::OwnerAsk::STATUS_WITHDRAWN, Chat::OwnerAsk.for_call(@chat, "call_1").status
  end

  test "the owner's message offers Agree and Say no until answered, then says how it went" do
    shown = Conversation::OwnerAsks::Shown.new(id: "a1", status: Chat::OwnerAsk::STATUS_ASKED, owner_name: "Bob Jones", asker_name: "Alice Smith",
                                               headline: "Alice Smith asked Halon to cancel workflow run 123, which you started.", reason: "It ships a bad build",
                                               answered_words: nil)
    actions = Slack::Messages::OwnerAsk.build(shown).find { |block| block[:type] == "actions" }[:elements].map { |element| element[:action_id] }
    assert_equal [ Identifiers::OWNER_AGREE, Identifiers::OWNER_DECLINE ], actions

    answered = Slack::Messages::OwnerAsk.build(shown.with(answered_words: "Bob Jones agreed."))
    assert_nil answered.find { |block| block[:type] == "actions" }
  end

  private

  def tool = Chat::Tools::Connection.new(@turn, @cancel)

  def cancel_call = RubyLLM::ToolCall.new(id: "call_1", name: @cancel.model_facing_name, arguments: ARGUMENTS.merge("intent" => "Stop the bad deploy"))

  def pause!
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
               .ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @cancel.model_facing_name, arguments: ARGUMENTS.merge("intent" => "Stop the bad deploy"))
    @chat.request_decisions!([ "call_1" ])
    @chat.tool_calls.find_by!(tool_call_id: "call_1")
  end

  def started_by(login, email: nil)
    Integrations::GithubApp.stubs(:get).with("/repos/acme/shop/actions/runs/123", token: "ghs_token")
             .returns({ "id" => 123, "name" => "Deploy", "run_number" => 9, "status" => "in_progress", "triggering_actor" => { "login" => login } })
    Integrations::GithubApp.stubs(:get).with("/users/#{login}", token: "ghs_token").returns({ "login" => login, "email" => email })
  end
end
