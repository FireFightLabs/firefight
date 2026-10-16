require "test_helper"

class Interactions::SkillProposalHandlersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @thread = @workspace.conversations.create!(subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id, thread_id: "1.1",
                                               started_by: @member, max_turns: 10, max_spend_cents: 50)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
    @content = { "when" => "Someone asks to rotate keys", "tools" => [ "declare_incident" ], "steps" => "1. Declare a maintenance incident with `declare_incident`." }
  end

  def propose!
    SkillProposalService.new(@workspace).propose!(@thread, name: "rotate_keys", content: @content, reason: "You rotated keys this way twice.")
  end

  test "a proposal from a chat in a thread is posted there, and the message is kept so a decision redraws it" do
    @adapter.expects(:post_skill_proposal).with { |channel_id:, thread_id:, proposal:|
      channel_id == @incident.channel_id && thread_id == "1.1" && proposal.name == "rotate_keys" && proposal.new_skill && proposal.decided.nil?
    }.returns(message_id: "2.2", channel_id: @incident.channel_id)

    proposal = perform_enqueued_jobs(only: SkillProposalPostJob) { propose! }

    assert_equal [ @incident.channel_id, "1.1", "2.2" ], proposal.reload.values_at(:channel_id, :thread_id, :message_id)
  end

  test "Accept makes the skill live as whoever pressed it and redraws the message saying so" do
    proposal = propose!
    proposal.update_columns(channel_id: @incident.channel_id, message_id: "2.2")
    @adapter.expects(:update_skill_proposal).with { |message_id:, proposal:, **| message_id == "2.2" && proposal.decided == "Accepted by #{@member.display_name}." }

    assert_nil Interactions::SkillProposalDecisionHandler.execute(click(proposal, Identifiers::SKILL_PROPOSAL_ACCEPT))

    assert_equal proposal, proposal.custom_skill.reload.live_version
  end

  test "Dismiss leaves the skills as they are, and pressing again tells only the presser how it was settled" do
    proposal = propose!
    proposal.update_columns(channel_id: @incident.channel_id, message_id: "2.2")
    @adapter.stubs(:update_skill_proposal)
    Interactions::SkillProposalDecisionHandler.execute(click(proposal, Identifiers::SKILL_PROPOSAL_DISMISS))
    @adapter.expects(:post_ephemeral).with(channel_id: @incident.channel_id, user_id: @member.platform_user_id, text: "This proposal was already decided.")

    Interactions::SkillProposalDecisionHandler.execute(click(proposal, Identifiers::SKILL_PROPOSAL_ACCEPT))

    assert_nil proposal.custom_skill.reload.live_version
  end

  test "a proposal someone overtook is not accepted from the message, with why" do
    skill = Chat::CustomSkill.create_with!(workspace: @workspace, name: "rotate_keys", content: @content, by: @member)
    proposal = propose!
    skill.write!(@content.merge("steps" => "1. Bob's way with `declare_incident`."), by: @member)
    @adapter.expects(:post_ephemeral).with { |text:, **| text.include?("changed since Halon proposed this") }

    Interactions::SkillProposalDecisionHandler.execute(click(proposal, Identifiers::SKILL_PROPOSAL_ACCEPT))

    assert proposal.reload.proposed?
  end

  test "a decision on the Skills page redraws the message in the thread" do
    proposal = propose!
    proposal.update_columns(channel_id: @incident.channel_id, message_id: "2.2")
    @adapter.expects(:update_skill_proposal).with { |proposal:, **| proposal.decided == "Dismissed by #{@member.display_name}." }

    SkillProposalService.new(@workspace).dismiss!(proposal, by: @member)
  end

  test "the message shows the skill, why, and Accept and Dismiss while it waits, and who decided once someone did" do
    shown = SkillProposalService.new(@workspace).shown(propose!)

    blocks = Slack::Messages::SkillProposal.build(shown)
    text = blocks.to_json
    assert_includes text, "Halon proposes a skill"
    assert_includes text, "rotate_keys"
    assert_includes text, "You rotated keys this way twice."
    assert_equal [ Identifiers::SKILL_PROPOSAL_ACCEPT, Identifiers::SKILL_PROPOSAL_DISMISS ], blocks.find { |block| block[:type] == "actions" }[:elements].filter_map { |button| button[:action_id] }
    assert_equal "divider", blocks.second[:type]

    decided = Slack::Messages::SkillProposal.build(shown.with(decided: "Accepted by Alice."))
    assert_nil decided.find { |block| block[:type] == "actions" && block[:elements].any? { |button| button[:action_id] } }
  end

  test "deciding needs the permission writing skills needs" do
    assert_equal [ Ability::Action::RESOURCE_SKILLS, Ability::Action::ACTION_UPDATE ], Interactions::SkillProposalDecisionHandler.authorization
  end

  private

  def click(proposal, action_id)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
                    channel_id: @incident.channel_id, message_id: "2.2", user_id: @member.platform_user_id,
                    action_id: action_id, action_value: proposal.id)
  end
end
