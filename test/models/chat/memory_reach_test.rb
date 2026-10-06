require "test_helper"

# A memory about a resource outside someone's map reach is hidden from them wherever memories are read or changed.
class Chat::MemoryReachTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    @hidden = remember("secret-db holds the card tokens", map_resource(@workspace, "secret-db"))
    @shown = remember("web keeps sessions in Redis", map_resource(@workspace, "web"))
    @entry = remember("Auth Service owns logins", catalog_entries(:auth_service))
    @everywhere = remember("Deploys freeze on Fridays", nil)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "a limited member's memories leave out the hidden resource's, and keep the catalog and workspace ones" do
    assert_equal [ @shown, @entry, @everywhere ].map(&:id).sort, Chat::Memory.visible_to(@member, @workspace).pluck(:id).sort
    assert_includes Chat::Memory.visible_to(SystemAgent.investigator, @workspace), @hidden
  end

  test "Halon's starting memories in a chat use the asker's reach, and a run's use the investigator's" do
    subjects = [ map_resource(@workspace, "secret-db"), map_resource(@workspace, "web") ]

    lines = Chat::Memory.starting_with(@workspace, subjects, principal: @member).map(&:line).join("\n")
    assert_includes lines, "web keeps sessions"
    assert_no_hidden(lines)
    assert_includes Chat::Memory.starting_with(@workspace, subjects, principal: SystemAgent.investigator), @hidden
    assert_no_hidden(Conversation::Runner.new(@conversation, asker: @member).send(:memories_line).to_s)
  end

  test "recall about a hidden resource answers as for nothing on the map, and a word search skips its memories" do
    recall = Chat::Tools::Recall.new(turn)

    assert_equal recall.call(about: "nothing-here").sub("nothing-here", "secret-db"), recall.call(about: "secret-db")
    assert_no_hidden(recall.call(words: "card tokens sessions"))
    assert_match "web keeps sessions", recall.call(words: "card tokens sessions")
  end

  test "disputing or correcting a hidden resource's memory answers as for a memory that does not exist" do
    [ Chat::Tools::DisputeMemory, Chat::Tools::CorrectMemory ].each do |tool|
      answer = tool.new(turn).call(memory: @hidden.id, reason: "wrong")
      assert_equal "There is no memory #{@hidden.id}.", answer
    end
    assert_equal Chat::Memory::STATE_CONFIRMED, @hidden.reload.state
  end

  test "remembering a fact about a hidden resource is refused as for a name not on the map, and nothing is saved" do
    remember_tool = Chat::Tools::Remember.new(turn)

    assert_equal remember_tool.call(fact: "It is in Frankfurt", about: "nothing-here").sub("nothing-here", "secret-db"),
                 remember_tool.call(fact: "It is in Frankfurt", about: "secret-db")
    assert_not(Chat::Memory.where(workspace: @workspace).to_a.any? { |memory| memory.text == "It is in Frankfurt" })
  end

  test "a lesson button or correction in Slack finds nothing when its memory is about a resource the presser cannot see" do
    incident = incidents(:active_critical_ws1)
    post = Chat::MemoryPost.create!(workspace: @workspace, incident: incident, kind: Chat::MemoryPost::KIND_INCIDENT, channel_id: incident.channel_id,
                                    memory_ids: [ @hidden.id ])
    service = MemoryPostService.new(@workspace)

    assert_not service.decide!(reference: post.id, memory_id: @hidden.id, member: @member, confirmed: false, channel_id: "C1", message_id: "1")
    assert_equal "That memory is gone. Close this and look on the Memory page.",
                 service.correct!(post_id: post.id, memory_id: @hidden.id, member: @member, correction: "It holds nothing", reason: nil)
    assert_equal Chat::Memory::STATE_CONFIRMED, @hidden.reload.state
  end

  private

  def turn = Conversation::Turn.new(@conversation, asker: @member)

  def remember(text, subject)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: Chat::Memory::STATE_CONFIRMED)
  end

  def assert_no_hidden(text)
    assert_not_includes text, "card tokens"
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes text, name }
  end
end
