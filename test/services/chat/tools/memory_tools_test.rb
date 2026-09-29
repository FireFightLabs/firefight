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

  test "a fact the person asked to remember is saved as confirmed by them, and one Halon worked out stays unconfirmed" do
    assert_equal "Remembered, confirmed by #{@member.display_name}.",
                 Chat::Tools::Remember.new(@turn).call("fact" => "Checkout runs in Frankfurt", "from_person" => true)
    Chat::Tools::Remember.new(@turn).call("fact" => "Checkout retries twice")

    assert_equal Chat::Memory::STATE_CONFIRMED, memory("Checkout runs in Frankfurt").state
    assert_equal @member, memory("Checkout runs in Frankfurt").confirmed_by
    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory("Checkout retries twice").state
  end

  test "a run cannot vouch for a fact, since nobody is there to" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)

    Chat::Tools::Remember.new(investigation).call("fact" => "Checkout runs in Frankfurt", "from_person" => true)

    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory("Checkout runs in Frankfurt").state
  end

  test "anything that looks like a secret is never remembered" do
    answer = Chat::Tools::Remember.new(@turn).call("fact" => "Prod is postgres://app:hunter2@db.internal:5432/app")

    assert_match "looks like it holds a secret (credential url)", answer[:error]
    assert_not Chat::Memory.exists?(workspace: @workspace)
  end

  test "a person correcting a memory rejects it with who and why, and the correction replaces it as theirs" do
    wrong = Chat::Memory.create!(workspace: @workspace, text: "firefight-prod is the dev database", state: Chat::Memory::STATE_UNCONFIRMED)

    answer = Chat::Tools::CorrectMemory.new(@turn).call("memory" => wrong.id, "reason" => "It is production", "correction" => "firefight-prod is the production database")

    assert_match "Corrected", answer
    wrong.reload
    assert_equal Chat::Memory::STATE_REJECTED, wrong.state
    assert_equal @member, wrong.rejected_by
    assert_equal "It is production", wrong.state_reason
    assert_equal Chat::Memory::STATE_CONFIRMED, wrong.replaced_by.state
    assert_equal "firefight-prod is the production database", wrong.replaced_by.text
    assert_equal "It was rejected already.", Chat::Tools::CorrectMemory.new(@turn).call("memory" => wrong.id, "reason" => "again")
  end

  test "forgetting rejects a memory without replacing it, and it is not learned again" do
    stale = Chat::Memory.create!(workspace: @workspace, text: "Checkout uses MySQL", state: Chat::Memory::STATE_CONFIRMED)

    assert_match "Forgotten", Chat::Tools::CorrectMemory.new(@turn).call("memory" => stale.id, "reason" => "We moved off MySQL")

    assert_nil stale.reload.replaced_by
    assert_match "A person rejected this before", Chat::Tools::Remember.new(@turn).call("fact" => "Checkout uses MySQL")
  end

  test "a chat starts with what the workspace remembers" do
    Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)

    context = Conversation::Runner.new(@conversation, asker: @member).send(:context)

    assert_match "What this workspace remembers", context
    assert_match "Deploys happen from main", context
  end

  private

  def memory(text) = Chat::Memory.where(workspace: @workspace).to_a.find { |each| each.text == text }
end
