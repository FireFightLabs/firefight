require "test_helper"

# Alice has Halon turn a PostHog flag off during an incident. It is undone after the time she picks unless someone keeps
# it, with a reminder before, through the tool Halon wrote the undo with, as her.
class Conversation::MitigationsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ARGUMENTS = { "id" => 7 }.freeze

  setup do
    # What this covers runs after a change was backed by a read, which Chat::Tools::LookFirstTest covers.
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
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

  test "the confirmation offers when it is undone in time order, starting on an hour, and the person's choice is kept" do
    call = pause!
    Chat::Safeguards.prepare!(@turn, [ call ])

    confirmation = Chat::Tools.confirmation(call)
    assert_equal [ "keep", "15", "60", "240", "1440" ], confirmation.expires.map(&:value)
    assert_equal [ "Never", "15 min", "1 h", "4 h", "24 h" ], confirmation.expires.map(&:label)
    assert_equal "60", confirmation.chosen_expiry
    assert_equal Chat::Tools::ASK_HALON_TO_PUT_BACK, confirmation.undo_label, "nothing fixed puts a flag back, so Halon is asked"

    Conversation::Confirming.decide(@conversation, [ { tool_call_id: "call_1", approved: true, expires: "240" } ], by: @alice)
    assert_equal 240, Chat::Mitigation.for_call(@chat, "call_1").duration_minutes
  end

  test "a time not offered falls back to the default" do
    assert_equal Chat::Mitigation::DEFAULT_MINUTES, Chat::Mitigation.chosen_minutes("999999")
    assert_nil Chat::Mitigation.chosen_minutes(Chat::Mitigation::KEEP)
  end

  test "once it runs its time starts, and with no fixed undo declared Halon puts it back in the chat, never a model's undo" do
    call = pause!
    Chat::Safeguards.prepare!(@turn, [ call ])
    call.update_columns(approval: Chat::APPROVAL_APPROVED)
    FirefightAi::UndoWriter.any_instance.expects(:write).never

    said = run!
    mitigation = Chat::Mitigation.for_call(@chat, "call_1")

    assert_match "Flag 7 (new-checkout) is now off.", said
    assert_match "Halon asks in this chat to put it back in 1 hour", said
    assert_no_match "Firefight undoes", said
    assert_equal Chat::Mitigation::STATUS_ACTIVE, mitigation.status
    assert_in_delta 1.hour.from_now, mitigation.expires_at, 5.seconds
    assert_equal [ Chat::Mitigation::UNDO_IN_CHAT, [] ], [ mitigation.undo_state, mitigation.undo_steps ]
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

  test "when its time is up with no fixed undo, Halon is asked in the chat, and the change stays in place until that call runs" do
    mitigation = in_chat!(expires_at: 1.minute.ago)

    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @alice.id ]) { Conversation::Mitigations.expire!(mitigation) }

    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status
    assert mitigation.live?, "nothing is put back until Halon's call runs"
    assert_nil mitigation.undo_blocked_reason(@alice), "Undo now stays offered"
    assert_match "which no fixed call puts back", @chat.messages.where(nudge: true).last.content
    assert_empty @sent
  end

  test "the call Halon makes to put it back is its undo, counted as undone only once it runs, and never a new temporary change" do
    mitigation = in_chat!(expires_at: 1.minute.ago)
    Conversation::Mitigations.expire!(mitigation)
    schema = Chat::Tools::Connection.new(@turn, @enable).parameters_schema
    assert_equal [ mitigation.id ], schema.dig("properties", Chat::Tools::PUTS_BACK_ARG, "enum"), "Halon is offered the change to name"
    back = undo_call!("call_back", puts_back: mitigation.id)
    Chat::Safeguards.prepare!(@turn, [ back ])
    assert_nil Chat::Mitigation.for_call(@chat, "call_back"), "putting something back is not itself counted down"
    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status

    said = run_enable!("call_back")

    assert_equal [ "feature_flag_enable", ARGUMENTS ], @sent.last, "the provider never sees which change it puts back"
    assert_equal Chat::Mitigation::STATUS_UNDONE, mitigation.reload.status
    assert_equal "Halon put Turn new-checkout off back.", mitigation.outcome
    assert_nil Chat::Mitigation.for_call(@chat, "call_back")
    assert_match "This put back Turn new-checkout off", said
  end

  test "a change on the same connection that names nothing to put back is its own change, counted down, and leaves the waiting one in place" do
    mitigation = in_chat!(expires_at: 1.minute.ago)
    Conversation::Mitigations.expire!(mitigation)
    other = pause!
    other.update_columns(tool_call_id: "call_other", approval: Chat::APPROVAL_APPROVED)
    Chat::Safeguards.prepare!(@turn, [ other ])
    assert Chat::Mitigation.for_call(@chat, "call_other"), "another flag turned off is counted down as any"

    tool = Chat::Tools::Connection.new(@turn, @disable)
    tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_other", name: tool.name, arguments: { "id" => 8 }), id: 8)

    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status
    assert_nil mitigation.undo_tool_call_id
    assert_equal Chat::Mitigation::STATUS_ACTIVE, Chat::Mitigation.for_call(@chat, "call_other").status
  end

  test "while the person is asked about another call, Halon is asked to put it back at its next turn, so that question is never withdrawn" do
    open = pause!
    open.update_columns(tool_call_id: "call_open")
    mitigation = in_chat!(expires_at: 1.minute.ago)
    mitigation.update_columns(tool_call_id: "call_earlier")

    assert_no_enqueued_jobs(only: ConversationReplyJob) { Conversation::Mitigations.expire!(mitigation) }

    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status
    assert_not @chat.messages.where(nudge: true).exists?, "nothing is added after the open question"
    assert_equal Chat::APPROVAL_REQUESTED, open.reload.approval
    assert_match "Put back only this change now", Conversation::Mitigations.untold_note(@chat)
    assert_nil Conversation::Mitigations.untold_note(@chat), "asked once"
  end

  test "Undo now pressed while another question is open says who pressed it when Halon is asked at its next turn" do
    open = pause!
    open.update_columns(tool_call_id: "call_open")
    mitigation = in_chat!(expires_at: 1.hour.from_now)
    mitigation.update_columns(tool_call_id: "call_earlier")

    assert_nil Conversation::Mitigations.undo_now!(mitigation, by: @alice)
    perform_enqueued_jobs(only: MitigationUndoRunJob)

    assert_match "#{@alice.display_name} pressed Undo now on Turn new-checkout off", Conversation::Mitigations.untold_note(@chat)
  end

  test "an undo call that fails, or never runs, leaves the change in place, due by hand, and Undo now asks Halon again" do
    mitigation = in_chat!(expires_at: 1.minute.ago)
    Conversation::Mitigations.expire!(mitigation)
    failing = Object.new
    failing.define_singleton_method(:call) { |**| { "isError" => true, "content" => [ { "type" => "text", "text" => "Flag 7 is locked." } ] } }
    Integration.any_instance.stubs(:executor).returns(failing)
    undo_call!("call_back", puts_back: mitigation.id)

    said = run_enable!("call_back")
    @chat.tool_calls.find_by!(tool_call_id: "call_back").update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: said.to_s))
    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status
    assert_nil mitigation.undo_tool_call_id, "the next call to put it back is tied to it instead"

    travel(Chat::Mitigation::REMIND_BEFORE + 1.minute) do
      Slack::WorkspaceAdapter.any_instance.expects(:post_mitigation_notice_to_user).once.with do |notice:, **|
        notice.kind == Conversation::Mitigations::KIND_REMINDER && notice.text.include?("is still in place") && notice.text.include?("by hand")
      end.returns({ channel_id: "D1", message_id: "1.2" })
      MitigationSweepJob.perform_now
      MitigationSweepJob.perform_now
    end
    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status

    assert_nil Conversation::Mitigations.undo_now!(mitigation, by: @alice)
    assert_enqueued_with(job: ConversationReplyJob) { perform_enqueued_jobs(only: MitigationUndoRunJob) }
    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, mitigation.reload.status
    assert_match "Alice", @chat.messages.where(nudge: true).last.content
  end

  test "a job queued for a model to write an undo puts the change back in the chat instead, and a model's step never runs" do
    mitigation = active!
    FirefightAi::UndoWriter.any_instance.expects(:write).never

    MitigationUndoJob.perform_now(mitigation.id)
    assert_equal Chat::Mitigation::UNDO_IN_CHAT, mitigation.reload.undo_state
    mitigation.destroy!

    written = active!(expires_at: 1.minute.ago).tap { |row| row.update!(undo_state: Chat::Mitigation::UNDO_READY,
                                                                       undo_steps: [ { "description" => "On", "action_key" => @enable.action_key, "arguments" => ARGUMENTS } ]) }
    assert_enqueued_with(job: ConversationReplyJob) { Conversation::Mitigations.expire!(written) }
    assert_equal Chat::Mitigation::STATUS_UNDO_ASKED, written.reload.status, "a model's step goes to the chat, not to failed"
    assert_empty @sent
  end

  test "a job left from before moves only a change still waiting for its undo, and the chat is redrawn" do
    waiting = active!
    Conversation::LiveDelivery.expects(:safeguard_moved).once

    MitigationUndoJob.perform_now(waiting.id)
    MitigationUndoJob.perform_now(waiting.id)

    assert_equal [ Chat::Mitigation::UNDO_IN_CHAT, Chat::Mitigation::IN_CHAT_NOTE ], [ waiting.reload.undo_state, waiting.undo_note ]
  end

  test "a declared undo runs in the environment the change ran in only when that environment is this workspace's" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    label = github.tools.create!(name: "label_issue", description: "Label", enabled: true, read_only: false, params_schema: { "type" => "object" })
    mine = catalog_entries(:production_env)
    theirs = CatalogEntry.create!(workspace: workspaces(:slack_workspace_two), catalog_type: catalog_types(:team_ws2), name: "Theirs", slug: "theirs", attributes: {})
    mitigation = active!
    mitigation.update_columns(action_key: label.action_key, arguments: { "repo" => "acme/shop", "number" => 1, "add" => [ "bug" ] })

    mitigation.update_columns(environment_id: mine.id)
    assert_equal mine.id, Conversation::Mitigations.send(:declared_undo, mitigation, {})["environment_id"]
    mitigation.update_columns(environment_id: theirs.id)
    assert_nil Conversation::Mitigations.send(:declared_undo, mitigation, {})["environment_id"]
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

  test "an undo an approval rule holds says it runs once approved, and approving it runs it with no Run to press" do
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: @enable.reload.ability_action)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    mitigation = ready!(expires_at: 1.minute.ago)
    mitigation.update_columns(chat_id: conversation.chat_record.id, asker_id: @bob.id, status: Chat::Mitigation::STATUS_UNDOING)
    Slack::WorkspaceAdapter.any_instance.stubs(:post_held_call_to_user).returns({ channel_id: "D1", message_id: "9.1" })

    Conversation::Mitigations.undo!(mitigation.reload, by: nil)

    assert_equal Chat::Mitigation::STATUS_UNDO_HELD, mitigation.reload.status
    assert_equal "Undoing Turn new-checkout off needs an approval, so it waits in the chat until someone approves it, and then it runs.",
      mitigation.outcome
    held = conversation.chat.held_calls.sole
    assert_enqueued_with(job: ConversationReplyJob, args: [ conversation.id, @bob.id, held.id ]) do
      perform_enqueued_jobs(only: AbilityApprovalResumptionJob) { held.approval.approve!(by: @alice) }
    end
    assert_equal Chat::HeldCall::STATUS_RUNNING, held.reload.status
    assert_empty held.offers
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

  test "a change made without asking offers Undo now alone in Slack, and none when nothing puts it back" do
    notice = Conversation::Mitigations::Notice.new(id: "m1", kind: Conversation::Mitigations::KIND_MADE, title: "Label issue 12 as a bug",
                                                   text: "Halon made it without asking.", live: true, conversation_id: nil, keeps: false, temporary: false)
    blocks = Slack::Messages::MitigationNotice.build(notice)
    actions = blocks.find { |block| block[:type] == "actions" }[:elements].map { |element| element[:action_id] }
    assert_equal [ Identifiers::MITIGATION_UNDO ], actions
    assert_match "Made without asking: Label issue 12 as a bug", blocks.first.dig(:text, :text)

    final = Slack::Messages::MitigationNotice.build(notice.with(undoable: false))
    assert_nil final.find { |block| block[:type] == "actions" }
  end

  test "a temporary change Halon was asked to put back is still titled one in Slack, offering Undo now alone, and asking Halon again" do
    mitigation = in_chat!(expires_at: 1.minute.ago)
    mitigation.update_columns(status: Chat::Mitigation::STATUS_UNDO_ASKED)

    notice = Conversation::Mitigations.notice(mitigation.reload, Conversation::Mitigations::KIND_UNDO_ASKED, "Halon is asked.")
    blocks = Slack::Messages::MitigationNotice.build(notice)

    assert_match "Temporary change: Turn new-checkout off", blocks.first.dig(:text, :text)
    undo = blocks.find { |block| block[:type] == "actions" }[:elements].sole
    assert_equal Identifiers::MITIGATION_UNDO, undo[:action_id]
    assert_equal Slack::Messages::MitigationNotice::ASKS_HALON, undo.dig(:confirm, :text, :text)
  end

  test "a change made without asking in a dashboard chat stays on its card, with no direct message" do
    Slack::WorkspaceAdapter.any_instance.expects(:post_mitigation_notice_to_user).never
    made = Chat::Mitigation.create!(chat: @chat, workspace: @workspace, asker: @alice, tool_call_id: "call_9", tool_name: @disable.model_facing_name,
                                    action_key: @disable.action_key, arguments: ARGUMENTS, status: Chat::Mitigation::STATUS_MADE, started_at: Time.current,
                                    undo_state: Chat::Mitigation::UNDO_NO_INVERSE, unasked_reason: Ability::Invocation::UNASKED_SAFE)

    notice = Conversation::Mitigations.tell!(made, Conversation::Mitigations::KIND_MADE, "Made.")

    assert_not notice.keeps
    assert_not notice.undoable
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

  def in_chat!(expires_at:)
    active!(expires_at: expires_at).tap { |row| row.update!(undo_state: Chat::Mitigation::UNDO_IN_CHAT, undo_note: Chat::Mitigation::IN_CHAT_NOTE) }
  end

  # Halon's call to turn the flag back on, approved on its card, naming the change it puts back.
  def undo_call!(call_id, puts_back:)
    @undo_arguments = ARGUMENTS.merge(Chat::Tools::PUTS_BACK_ARG => puts_back)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: call_id, name: @enable.model_facing_name, arguments: @undo_arguments.merge("intent" => "Turn new-checkout back on"),
                                        approval: Chat::APPROVAL_APPROVED)
  end

  def run_enable!(call_id)
    tool = Chat::Tools::Connection.new(@turn, @enable)
    tool.call(tool_call: RubyLLM::ToolCall.new(id: call_id, name: tool.name, arguments: @undo_arguments), **@undo_arguments.symbolize_keys)
  end

  def ready!(expires_at:)
    active!(expires_at: expires_at).tap do |mitigation|
      mitigation.update!(undo_state: Chat::Mitigation::UNDO_READY, undo_note: "Turn new-checkout back on",
                         undo_steps: [ { "description" => "Turn new-checkout back on", "action_key" => @enable.action_key, "arguments" => ARGUMENTS, "declared" => true } ])
    end
  end

  def interaction(action_id, mitigation, member)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: member.platform_user_id,
                    action_id: action_id, action_value: mitigation.id, channel_id: "D1", message_id: "1.1")
  end
end
