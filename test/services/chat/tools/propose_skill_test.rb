require "test_helper"

class Chat::Tools::ProposeSkillTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  def propose(turn = @turn, **overrides)
    Chat::Tools::ProposeSkill.new(turn).call(
      "name" => "rotate_keys", "when" => "Someone asks to rotate the API keys", "tools" => [ "declare_incident" ],
      "steps" => "1. Declare a maintenance incident with `declare_incident`.", "reason" => "You rotated keys this way twice.", **overrides
    )
  end

  test "in a dashboard chat it proposes the skill as a card there, and nothing changes until a person accepts it" do
    answer = nil
    assert_broadcasts(ConversationChannel.broadcasting_for(@conversation), 1) { answer = propose }

    assert_equal "Proposed. A card in this chat asks the person to accept, edit or dismiss it, and so does the Skills page. " \
                 "Until someone accepts it, the skill stays as it is.", answer
    proposal = @conversation.skill_proposals.sole
    assert_equal [ "rotate_keys", "You rotated keys this way twice." ], [ proposal.custom_skill.name, proposal.reason ]
    assert_not_includes Chat::Skill.available_to(@workspace).map(&:name), "rotate_keys"
  end

  test "in a channel's chat it points at the Skills page" do
    AppUrl.stubs(:options).returns(host: "firefight.test", protocol: "https")
    channel = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, channel_id: "C0OPS", thread_id: "1.1", max_turns: 5, max_spend_cents: 5)

    assert_match "It waits on the Skills page in Firefight (https://firefight.test/app/halon/skills)", propose(Conversation::Turn.new(channel, asker: @member))
  end

  test "a change to one of Firefight's skills proposes the workspace's copy of it" do
    propose("name" => "declaring", "steps" => "1. Our way, with `declare_incident`.")

    skill = Chat::CustomSkill.find_by!(workspace: @workspace, name: "declaring")
    assert_equal [ "declaring", nil ], [ skill.library_name, skill.live_version ]
  end

  test "the same proposal is not made twice from one chat, and one that does not hold is refused with why" do
    propose
    assert_equal "You already proposed rotate_keys here, and it still waits on a person.", propose

    answer = propose("name" => "other", "tools" => [ "launch_rockets" ])
    assert_match "launch_rockets is not a tool Halon has in this workspace", answer
    assert_match "Nothing was proposed.", answer
  end

  test "it is offered only with the workflows flag" do
    assert_equal [ Chat::Tools::ProposeSkill ], Chat::Tools::ProposeSkill.all(@turn).map(&:class)

    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    assert_empty Chat::Tools::ProposeSkill.all(@turn)
  end
end
