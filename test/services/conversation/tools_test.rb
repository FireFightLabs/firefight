require "test_helper"

class Conversation::ToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @conversation = @workspace.conversations.create!(
      subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id,
      thread_id: "1700000000.000100", started_by: workspace_memberships(:alice_workspace_one),
      max_turns: 40, max_spend_cents: 50
    )
    FeatureFlags.stubs(:enabled?).returns(true)
    Entitlements.stubs(:allows?).returns(true)
    Ability::Grant.create!(
      workspace: @workspace, principal: workspace_memberships(:alice_workspace_one),
      action: Ability::Action.system!(
        Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
      )
    )
  end

  test "a conversation starts with only the tools it always needs" do
    names = Conversation::Tools.for(turn, offer: ->(_tools) { }).map(&:name)

    assert_equal [ "open_tools", "use_skill", "read_result", "start_investigation", "remember", "recall", "dispute_memory", "correct_memory",
                   "search_web", "read_web_page" ], names
  end

  test "opening a group points at the skills with the steps for its tools, in a chat and in a run, since both hold use_skill" do
    Chat::Tools.stubs(:catalog).returns([
      Chat::Tools::Entry.new(name: "declare_incident", description: "Declare", state: Chat::Tools::STATE_READY, tool: nil,
                             group: Chat::Tools::Groups::INCIDENT_RESPONSE, source: Chat::Skill::SOURCE_FIREFIGHT, handle: "declare_incident")
    ])
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    [ turn, run ].each do |agent_run|
      opened = Chat::Tools::Open.new(agent_run, offer: ->(_tools) { }).call("group" => Chat::Tools::Groups::INCIDENT_RESPONSE)

      assert_includes opened, "Load the one that fits the question with use_skill first"
      assert_includes opened, "declaring: "
    end
  end

  test "a group too large to open whole still points at its skills, which load the tools themselves" do
    entries = (1..(Chat::Tools::Open::LARGE_GROUP + 1)).map do |number|
      Chat::Tools::Entry.new(name: "declare_incident_#{number}", description: "Declare", state: Chat::Tools::STATE_READY, tool: nil,
                             group: Chat::Tools::Groups::INCIDENT_RESPONSE, source: Chat::Skill::SOURCE_FIREFIGHT, handle: "declare_incident")
    end
    Chat::Tools.stubs(:catalog).returns(entries)

    answer = Chat::Tools::Open.new(turn, offer: ->(_tools) { }).call("group" => Chat::Tools::Groups::INCIDENT_RESPONSE)

    assert_includes answer, "This group is large, so nothing was loaded"
    assert_includes answer, "declaring: "
  end

  test "someone who may not start a run is refused, in their name" do
    AbilityGateway.stubs(:permitted?).returns(false)

    assert_no_difference "Investigation.count" do
      assert_match "not allowed to start an investigation", tool.call[:error]
    end
  end

  test "a member starts a run from a chat without any grant, and one an admin took it away from is refused, in their name" do
    bob = workspace_memberships(:bob_workspace_one)
    as_bob = Conversation::Tools::StartInvestigation.new(Conversation::Turn.new(@conversation, asker: bob))

    assert_match "Started", as_bob.call
    assert_equal bob, @workspace.investigations.sole.triggered_by

    @workspace.investigations.sole.finish!(status: Investigation::STATUS_SUCCEEDED)
    take_halon_from(@workspace, bob)
    assert_no_difference "Investigation.count" do
      assert_equal "#{bob.display_name} is not allowed to start an investigation.", as_bob.call[:error]
    end
  end

  test "a run that needs approval is not started until someone approves it" do
    start = Ability::Action.system!(
      Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
    )
    @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals").policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ start.risk_level ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )

    assert_no_difference "Investigation.count" do
      assert_match "not allowed to start an investigation", tool.call[:error]
    end
  end

  test "starting a run is written to the ledger and closed off" do
    tool.call

    invocation = @workspace.ability_invocations.find_by!(action_key: Ability::Action.system_key(
      Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
    ))
    assert_equal Ability::Invocation::DECISION_ALLOW, invocation.decision
    assert invocation.completed_at
  end

  test "the chat hands over what the person said, so the run starts from it" do
    # RubyLLM hands arguments over keyed by text.
    tool.call(**{ "symptom" => "checkout is slow", "started_around" => "2026-09-24T12:00:00Z", "names" => [ "checkout" ] })

    brief = @workspace.investigations.sole.brief
    assert_equal "checkout is slow", brief[Investigation::Brief::KEY_SYMPTOM]
    assert_equal "2026-09-24T12:00:00Z", brief[Investigation::Brief::KEY_STARTED_AROUND]
    assert_equal Investigation::Brief::SOURCE_CHAT, brief[Investigation::Brief::KEY_SOURCE]
  end

  test "the agent can hand a question over to a full investigation" do
    assert_difference "Investigation.count", 1 do
      assert_match "Started", tool.call
    end

    investigation = @workspace.investigations.sole
    assert_equal @incident, investigation.subject
    assert_equal @conversation.started_by, investigation.triggered_by
    assert_equal Investigation::TRIGGER_CONVERSATION, investigation.trigger_source
  end

  test "a run started from a chat is handed its own copy of every file shared in the chat, and one it will not read says why" do
    member = workspace_memberships(:alice_workspace_one)
    log = Chat::Attachment.take!(workspace: @workspace, uploaded_by: member, filename: "app.log", bytes: "pool exhausted at 10:02")
    @conversation.ask!("what broke?", asker: member, files: [ log ])
    @conversation.reply_delivered!
    dump = Chat::Attachment.unread!(workspace: @workspace, uploaded_by: member, filename: "core.dump", byte_size: 9, refusal: "core.dump is not a file Halon reads.")
    @conversation.ask!("and this", asker: member, files: [ dump ])

    tool.call

    run = @workspace.investigations.sole
    handed = run.notes.sole.attached_files.to_a
    assert_equal %w[app.log core.dump], handed.map(&:filename)
    assert_not_includes handed.map(&:id), log.id, "the chat keeps its own file"
    assert_equal "pool exhausted at 10:02", handed.first.bytes
    assert_equal "core.dump is not a file Halon reads.", handed.last.refusal

    run.take_notes!
    read = run.chat.messages.where(role: Chat::Message::ROLE_USER).sole.to_llm.content
    assert_match "Alice Smith added: #{Investigation::Noting::FILES_WITH_THE_ASK}", read
    assert_match "pool exhausted at 10:02", read
    assert_equal @conversation.chat, log.reload.chat
  end

  test "a chat with no files starts a run with nothing waiting on it" do
    tool.call

    assert_empty @workspace.investigations.sole.notes
  end

  test "a run already going is said plainly rather than started twice" do
    tool.call

    assert_equal Investigation.already_running_message(@incident), tool.call[:error]
  end

  test "a chat about no incident investigates what the person said, and the answer comes back to it" do
    @conversation.update!(subject: nil)

    tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_7", name: Mcp::Tools::START_INVESTIGATION, arguments: {}), symptom: "checkout is slow")

    investigation = @conversation.investigations.sole
    assert_nil investigation.subject
    assert_equal "checkout is slow", investigation.question
    assert_equal "call_7", investigation.tool_call_id
  end

  test "a chat about no incident needs to be told what is wrong" do
    @conversation.update!(subject: nil)

    assert_no_difference "Investigation.count" do
      assert_match "symptom", tool.call[:error]
    end
  end

  # The refusal still goes to the model as text, so without the mark the card would say Completed.
  test "a refusal is remembered as failed on the saved call" do
    @conversation.update!(subject: nil)
    call = RubyLLM::ToolCall.new(id: "call_1", name: Mcp::Tools::START_INVESTIGATION, arguments: {})
    @conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => call }))

    tool.call(tool_call: call)

    assert_equal [ "call_1" ], @conversation.chat.failed_tool_call_ids
  end

  private

  def turn = Conversation::Turn.new(@conversation, asker: workspace_memberships(:alice_workspace_one))

  def tool = Conversation::Tools::StartInvestigation.new(turn)
end
