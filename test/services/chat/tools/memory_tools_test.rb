require "test_helper"

class Chat::Tools::MemoryToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  test "remember saves a fact unconfirmed, about what it names, with the chat and the person who taught it" do
    answer = Chat::Tools::Remember.new(@turn).call("fact" => "Auth Service keeps sessions in Redis", "about" => "auth service")

    assert_equal "Remembered, unconfirmed until a person confirms it.", answer
    memory = Chat::Memory.find_by!(workspace: @workspace)
    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.state
    assert_equal catalog_entries(:auth_service), memory.subject
    assert_equal @conversation, memory.source
    assert_equal @member, memory.added_by
  end

  test "remember does not save twice, never saves what a person rejected, and says when it could not find what it is about" do
    Chat::Tools::Remember.new(@turn).call("fact" => "Deploys happen from main")
    assert_equal "Already remembered.", Chat::Tools::Remember.new(@turn).call("fact" => "deploys happen from MAIN")

    Chat::Memory.create!(workspace: @workspace, text: "Checkout uses MySQL", state: Chat::Memory::STATE_REJECTED, state_reason: "It is Postgres")
    assert_match "A person rejected this before: It is Postgres", Chat::Tools::Remember.new(@turn).call("fact" => "Checkout uses MySQL")

    assert_match "Nothing called ledger is on the map or in the catalog", Chat::Tools::Remember.new(@turn).call("fact" => "Ledger is slow on Mondays", "about" => "ledger")
  end

  test "recall reads memories with whether a person confirmed them, and dispute takes one out of use" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Auth Service keeps sessions in Redis", state: Chat::Memory::STATE_CONFIRMED,
                                  subject: catalog_entries(:auth_service), confirmed_by: @member)

    recalled = Chat::Tools::Recall.new(@turn).call("about" => "Auth Service")
    assert_includes recalled, "confirmed by #{@member.display_name}"
    assert_equal 1, memory.reload.use_count

    assert_match "Disputed", Chat::Tools::DisputeMemory.new(@turn).call("memory" => memory.id, "reason" => "Sessions are in Postgres")
    assert_equal "Nothing is remembered about that yet.", Chat::Tools::Recall.new(@turn).call("about" => "Auth Service")
  end

  test "a chat starts with what the workspace remembers" do
    Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)

    context = Conversation::Runner.new(@conversation, asker: @member).send(:context)

    assert_match "What this workspace remembers", context
    assert_match "Deploys happen from main", context
  end
end
