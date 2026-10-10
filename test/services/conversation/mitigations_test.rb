require "test_helper"

# Alice has Halon turn a PostHog flag off during an incident. It is undone after the time she picks unless someone keeps
# it, with a reminder before, through the tool Halon wrote the undo with, as her.
class Conversation::MitigationsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ARGUMENTS = { "id" => 7 }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record
    posthog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog",
                                              settings: { "server_url" => "https://mcp.posthog.com/mcp?mode=tools" })
    posthog.integration_environments.create!
    schema = { "type" => "object", "properties" => { "id" => { "type" => "integer" } } }
    @disable = posthog.tools.create!(name: "feature_flag_disable", description: "Disable a flag", enabled: true, read_only: false, params_schema: schema)
    @enable = posthog.tools.create!(name: "feature_flag_enable", description: "Enable a flag", enabled: true, read_only: false, params_schema: schema)
    @sent = []
    sent = @sent
    executor = Object.new
    executor.define_singleton_method(:call) do |tool:, arguments:, **|
      sent << [ tool.name, arguments ]
      { "content" => [ { "type" => "text", "text" => "Flag 7 (new-checkout) is now #{tool.name.end_with?('disable') ? 'off' : 'on'}." } ] }
    end
    Integration.any_instance.stubs(:executor).returns(executor)
    Slack::WorkspaceAdapter.any_instance.stubs(:post_mitigation_notice_to_user).returns({ channel_id: "D1", message_id: "1.1" })
  end

  test "the registry's mitigation tools give their actions the effect, by the tool and never the provider" do
    assert @disable.reload.ability_action.effect?(Ability::Action::EFFECT_MITIGATION)
    assert_not @disable.ability_action.effect?(Ability::Action::EFFECT_STOPS)
    assert_not Ability::Action.lookup("incidents.update", @workspace).effect?(Ability::Action::EFFECT_MITIGATION)
  end

  test "the confirmation offers when it is undone, an hour first, and the person's choice is kept" do
    call = pause!
    Chat::Safeguards.prepare!(@turn, [ call ])

    expires = Chat::Tools.confirmation(call).expires
    assert_equal [ "60", "15", "240", "1440", "keep" ], expires.map(&:value)
    assert_equal "Undo after 1 hour", expires.first.label
    assert_equal "Keep it", expires.last.label

    Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true, expires: "240" } ], by: @alice)
    assert_equal 240, Chat::Mitigation.for_call(@chat, "call_1").duration_minutes
  end

  test "a time not offered falls back to the default" do
    assert_equal Chat::Mitigation::DEFAULT_MINUTES, Chat::Mitigation.chosen_minutes("999999")
    assert_nil Chat::Mitigation.chosen_minutes(Chat::Mitigation::KEEP)
  end

  test "once it runs its time starts, its undo is written, and Halon is told when it ends" do
    call = pause!
    Chat::Safeguards.prepare!(@turn, [ call ])
    call.update_columns(approval: Chat::APPROVAL_APPROVED)

    said = nil
    assert_enqueued_with(job: MitigationUndoJob) { said = run! }
    mitigation = Chat::Mitigation.for_call(@chat, "call_1")

    assert_match "Flag 7 (new-checkout) is now off.", said
    assert_match "Firefight undoes this in 1 hour", said
    assert_equal Chat::Mitigation::STATUS_ACTIVE, mitigation.status
    assert_in_delta 1.hour.from_now, mitigation.expires_at, 5.seconds
    assert_equal Chat::Mitigation::UNDO_WRITING, mitigation.undo_state
  end

  test "a call that runs without a pause, such as one allowed for the chat, is kept with the default time" do
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
               .ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @disable.model_facing_name, arguments: ARGUMENTS.merge("intent" => "Turn new-checkout off"))

    run!

    mitigation = Chat::Mitigation.for_call(@chat, "call_1")
    assert_equal Chat::Mitigation::STATUS_ACTIVE, mitigation.status
    assert_equal "Turn new-checkout off", mitigation.title
  end

  test "a change the person chose to keep is never undone" do
    call = pause!
    Chat::Safeguards.prepare!(@turn, [ call ])
    Conversation::Mitigations.choose!(@chat, "call_1", Chat::Mitigation::KEEP)
    call.update_columns(approval: Chat::APPROVAL_APPROVED)

    assert_match "The person chose to keep this", run!
    mitigation = Chat::Mitigation.for_call(@chat, "call_1")
    assert_equal Chat::Mitigation::STATUS_KEPT, mitigation.status
    assert_nil mitigation.expires_at
    assert_empty Chat::Mitigation.expiry_due.where(id: mitigation.id)
  end

  test "the undo is written from what the change returned, checked against what the workspace can run" do
    mitigation = active!
    FirefightAi::UndoWriter.any_instance.expects(:write).with do |steps, tools:, **|
      steps.sole.result.include?("now off") && tools.include?(@enable.model_facing_name)
    end.returns({ "summary" => "Turn it back on", "steps" => [ { "kind" => "action", "description" => "Turn new-checkout back on",
                                                                 "tool" => @enable.model_facing_name, "arguments" => ARGUMENTS } ] })

    MitigationUndoJob.perform_now(mitigation.id)

    assert_equal Chat::Mitigation::UNDO_READY, mitigation.reload.undo_state
    assert_equal @enable.action_key, mitigation.undo_steps.sole["action_key"]
  end

  test "an undo only a person can do leaves it by hand, said with what to do" do
    mitigation = active!
    FirefightAi::UndoWriter.any_instance.stubs(:write).returns({ "steps" => [ { "kind" => "manual", "description" => "Turn the flag on in PostHog", "missing" => "No tool turns it on." } ] })

    MitigationUndoJob.perform_now(mitigation.id)

    assert_equal Chat::Mitigation::UNDO_BY_HAND, mitigation.reload.undo_state
    assert_match "Undo it by hand: Turn the flag on in PostHog No tool turns it on.", mitigation.undo_note
    assert_match "Halon could not write an undo it can run itself", mitigation.undo_blocked_reason(@alice)
  end

  test "it is reminded about once before it runs out, and undone as the asker when it does" do
    mitigation = ready!(expires_at: 10.minutes.from_now)
    Slack::WorkspaceAdapter.any_instance.expects(:post_mitigation_notice_to_user).once.with do |user_id:, notice:|
      user_id == @alice.platform_user_id && notice.kind == Conversation::Mitigations::KIND_REMINDER && notice.text.include?("ends in about 10 minutes")
    end.returns({ channel_id: "D1", message_id: "1.1" })

    MitigationSweepJob.perform_now
    MitigationSweepJob.perform_now
    assert mitigation.reload.reminded_at

    mitigation.update_columns(expires_at: 1.minute.ago)
    Slack::WorkspaceAdapter.any_instance.stubs(:post_mitigation_notice_to_user).returns({ channel_id: "D1", message_id: "1.2" })
    perform_enqueued_jobs(only: MitigationExpiryJob) { MitigationSweepJob.perform_now }

    assert_equal Chat::Mitigation::STATUS_UNDONE, mitigation.reload.status
    assert_equal [ "feature_flag_enable", ARGUMENTS ], @sent.last
    assert_match "Time was up, so Firefight undid Turn new-checkout off", mitigation.outcome
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: @enable.action_key, principal_id: @alice.id)
    assert_match "Turn new-checkout off: Time was up", Conversation::Mitigations.untold_note(@chat)
    assert_nil Conversation::Mitigations.untold_note(@chat), "an end is told once"
  end

  test "one due by hand is said so when it runs out, and nothing is run" do
    mitigation = active!(expires_at: 1.minute.ago)
    mitigation.update!(undo_state: Chat::Mitigation::UNDO_BY_HAND, undo_note: "Undo it by hand: Turn the flag on in PostHog.")

    Conversation::Mitigations.expire!(mitigation)

    assert_equal Chat::Mitigation::STATUS_DUE_BY_HAND, mitigation.reload.status
    assert_match "Turn the flag on in PostHog", mitigation.outcome
    assert_empty @sent
  end

  test "keep, more time and undo now are for whoever asked in their own chat, and each says why not" do
    mitigation = ready!(expires_at: 30.minutes.from_now)

    assert_match "Only Alice Smith can change this", Conversation::Mitigations.keep!(mitigation, by: @bob)
    assert_nil Conversation::Mitigations.extend!(mitigation, by: @alice)
    assert_in_delta 90.minutes.from_now, mitigation.reload.expires_at, 5.seconds
    assert_nil Conversation::Mitigations.keep!(mitigation, by: @alice)
    assert_equal Chat::Mitigation::STATUS_KEPT, mitigation.reload.status
    assert_equal "It is already kept.", mitigation.keep_blocked_reason(@alice)

    assert_enqueued_with(job: MitigationUndoRunJob, args: [ mitigation.id ]) { assert_nil Conversation::Mitigations.undo_now!(mitigation, by: @alice) }
    MitigationUndoRunJob.perform_now(mitigation.id)
    assert_equal Chat::Mitigation::STATUS_UNDONE, mitigation.reload.status
    assert_match "Alice Smith undid", mitigation.outcome
  end

  test "an undo a worker died in the middle of is ended saying it may or may not have gone through" do
    mitigation = ready!(expires_at: 1.hour.ago)
    mitigation.update_columns(status: Chat::Mitigation::STATUS_UNDOING, claimed_at: 1.hour.ago)

    MitigationSweepJob.perform_now

    assert_equal Chat::Mitigation::STATUS_UNDO_FAILED, mitigation.reload.status
    assert_match "may or may not be undone", mitigation.outcome
  end

  test "Slack's buttons on its notices do the same, and tell someone who may not why" do
    mitigation = ready!(expires_at: 30.minutes.from_now)
    Slack::WorkspaceAdapter.any_instance.stubs(:update_mitigation_notice).returns({ success: true })
    Slack::WorkspaceAdapter.any_instance.expects(:post_ephemeral).with { |text:, **| text.include?("Only Alice Smith can change this") }

    Interactions::MitigationHandler.execute(interaction(Identifiers::MITIGATION_KEEP, mitigation, @bob))
    assert mitigation.reload.active?

    Interactions::MitigationHandler.execute(interaction(Identifiers::MITIGATION_KEEP, mitigation, @alice))
    assert mitigation.reload.kept?
    assert_equal Interactions::MitigationHandler, InteractionDispatcher::BLOCK_ACTION_HANDLERS.fetch(Identifiers::MITIGATION_UNDO)
  end

  test "a reminder in Slack offers Keep it, One more hour and Undo now, and an ended one none" do
    notice = Conversation::Mitigations::Notice.new(id: "m1", kind: Conversation::Mitigations::KIND_REMINDER, title: "Turn new-checkout off",
                                                   text: "It ends in about 15 minutes.", live: true, conversation_id: nil)
    actions = Slack::Messages::MitigationNotice.build(notice).find { |block| block[:type] == "actions" }[:elements].map { |element| element[:action_id] }
    assert_equal [ Identifiers::MITIGATION_KEEP, Identifiers::MITIGATION_EXTEND, Identifiers::MITIGATION_UNDO ], actions

    ended = Slack::Messages::MitigationNotice.build(notice.with(live: false))
    assert_nil ended.find { |block| block[:type] == "actions" }
  end

  private

  def pause!
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @disable.model_facing_name, arguments: ARGUMENTS.merge("intent" => "Turn new-checkout off"))
    @chat.request_decisions!([ "call_1" ])
    @chat.tool_calls.find_by!(tool_call_id: "call_1")
  end

  def run!
    tool = Chat::Tools::Connection.new(@turn, @disable)
    tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_1", name: tool.name, arguments: ARGUMENTS), **ARGUMENTS.symbolize_keys)
  end

  def active!(expires_at: 1.hour.from_now)
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: "call_1", tool_name: @disable.model_facing_name,
                             action_key: @disable.action_key, arguments: ARGUMENTS, intent: "Turn new-checkout off", duration_minutes: 60,
                             status: Chat::Mitigation::STATUS_ACTIVE, started_at: Time.current, expires_at: expires_at,
                             result: "Flag 7 (new-checkout) is now off.", undo_state: Chat::Mitigation::UNDO_WRITING)
  end

  def ready!(expires_at:)
    active!(expires_at: expires_at).tap do |mitigation|
      mitigation.update!(undo_state: Chat::Mitigation::UNDO_READY, undo_note: "Turn new-checkout back on",
                         undo_steps: [ { "description" => "Turn new-checkout back on", "action_key" => @enable.action_key, "arguments" => ARGUMENTS } ])
    end
  end

  def interaction(action_id, mitigation, member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: action_id, action_value: mitigation.id, channel_id: "D1", message_id: "1.1")
  end
end
