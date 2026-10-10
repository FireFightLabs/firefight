require "test_helper"

class Chat::Tools::MemoryToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

    assert_equal "Nothing called ledger is on the map or in the catalog. Nothing was saved. Name what it is about, or leave about out to save it for the whole workspace.",
                 Chat::Tools::Remember.new(@turn).call("fact" => "Ledger is slow on Mondays", "about" => "ledger")
    assert_not Chat::Memory.where(workspace: @workspace).any? { |memory| memory.text.include?("Ledger") }
  end

  test "remember refuses a name several things share, listing their ids, and saves nothing" do
    other = @workspace.catalog_entries.create!(catalog_type: catalog_entries(:auth_service).catalog_type, name: "Auth Service", slug: "auth-service-eu")

    answer = Chat::Tools::Remember.new(@turn).call("fact" => "Sessions live in Redis", "about" => "Auth Service")

    assert_match "More than one thing is called Auth Service", answer
    assert_includes answer, other.id
    assert_includes answer, catalog_entries(:auth_service).id
    assert_not Chat::Memory.exists?(workspace: @workspace)
  end

  test "remember says why a live value or a fact about a person is not kept" do
    assert_equal Chat::Memory::Screening::LIVE_VALUE, Chat::Tools::Remember.new(@turn).call("fact" => "Checkout currently runs 3 replicas")
    assert_equal Chat::Memory::Screening::ABOUT_A_PERSON, Chat::Tools::Remember.new(@turn).call("fact" => "Ask ops@example.com before deploys")
    assert_not Chat::Memory.exists?(workspace: @workspace)
  end

  test "a chat about an incident tells its channel what it learned and disputed, and one elsewhere does not" do
    incident = incidents(:active_critical_ws1)
    in_incident = Conversation::Turn.new(Conversation.create!(workspace: @workspace, kind: Conversation::KIND_PERSONAL, subject: incident, started_by: @member,
                                                              max_turns: 10, max_spend_cents: 100), asker: @member)

    assert_enqueued_jobs(1, only: MemoryNoteJob) { Chat::Tools::Remember.new(in_incident).call("fact" => "Deploys happen from main") }
    memory = Chat::Memory.find_by!(workspace: @workspace)
    assert_enqueued_with(job: MemoryNoteJob, args: [ memory.id, Chat::MemoryPost::KIND_DISPUTED, in_incident.conversation ]) do
      Chat::Tools::DisputeMemory.new(in_incident).call("memory" => memory.id, "reason" => "Deploys go from release")
    end
    assert_no_enqueued_jobs(only: MemoryNoteJob) { Chat::Tools::Remember.new(@turn).call("fact" => "Checkout retries twice") }
  end

  test "recall about a resource gone from the map says so, and still finds what was remembered about it" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    ledger = ResourceMap::Resource.create!(workspace: @workspace, integration_environment: integration.integration_environments.create!, provider: "northflank",
                                           account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "ledger", name: "ledger", first_seen_at: 2.days.ago,
                                           last_seen_at: 2.days.ago, removed_at: 1.day.ago)
    Chat::Memory.create!(workspace: @workspace, text: "ledger writes to the orders database", subject: ledger, state: Chat::Memory::STATE_OUTDATED)

    answer = Chat::Tools::Recall.new(@turn).call("about" => "ledger")

    assert_match "ledger is no longer on the map. It was last seen #{1.day.ago.to_date.iso8601}", answer
    assert_match "ledger writes to the orders database", answer
  end

  test "recall says how many more matched than it shows" do
    25.times { |index| Chat::Memory.create!(workspace: @workspace, text: "Queue #{index} drains into the ledger", state: Chat::Memory::STATE_UNCONFIRMED) }

    answer = Chat::Tools::Recall.new(@turn).call("words" => "ledger")

    assert_equal Chat::Memory::STARTING_LIMIT + 1, answer.lines.size
    assert_match "5 more matched", answer
  end

  test "a change to memory in a chat is authorized as the asker and ledgered, without the fact's words" do
    Chat::Tools::Remember.new(@turn).call("fact" => "Deploys happen from main", "about" => "auth service")

    invocation = Ability::Invocation.where(workspace: @workspace, action_key: "memory.create").sole
    assert_equal @member.id, invocation.principal_id
    assert_not_includes invocation.params.to_json, "Deploys happen from main"
  end

  test "an approval rule never holds Halon saving, correcting or disputing a memory, and each change is still ledgered" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)

    assert_equal "Remembered, unconfirmed until a person confirms it.", Chat::Tools::Remember.new(@turn).call("fact" => "Deploys happen from main")
    corrected = memory("Deploys happen from main")
    assert_match "Corrected", Chat::Tools::CorrectMemory.new(@turn).call("memory" => corrected.id, "reason" => "Deploys go from release", "correction" => "Deploys happen from release")
    assert_equal "Remembered, unconfirmed until a person confirms it.", Chat::Tools::Remember.new(investigation).call("fact" => "Checkout runs in Frankfurt")
    assert_match "Disputed", Chat::Tools::DisputeMemory.new(investigation).call("memory" => memory("Checkout runs in Frankfurt").id, "reason" => "The deploy log shows Dublin")

    assert_equal Chat::Memory::STATE_REJECTED, corrected.reload.state
    assert_not @workspace.ability_approvals.exists?
    assert_equal [ Ability::Invocation::DECISION_ALLOW ],
                 @workspace.ability_invocations.where(action_key: %w[memory.create memory.update]).distinct.pluck(:decision)
    assert_equal 4, @workspace.ability_invocations.where(action_key: %w[memory.create memory.update]).count
  end

  test "a chat whose asker the gateway refuses changes no memory and is told why" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Checkout uses MySQL", state: Chat::Memory::STATE_UNCONFIRMED)
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::Denied.new("memory.update"))

    answer = Chat::Tools::CorrectMemory.new(@turn).call("memory" => memory.id, "reason" => "It is Postgres")

    assert_match "cannot use memory.update", answer
    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.reload.state
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

  test "a run saves what it learns unconfirmed through the gateway, as the investigator, and the change is in the activity log" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)

    assert_equal "Remembered, unconfirmed until a person confirms it.", Chat::Tools::Remember.new(investigation).call("fact" => "Checkout runs in Frankfurt")

    memory = memory("Checkout runs in Frankfurt")
    assert_equal [ Chat::Memory::STATE_UNCONFIRMED, investigation, nil ], [ memory.state, memory.source, memory.added_by ]
    entry = @workspace.ability_invocations.find_by!(action_key: "memory.create", principal: SystemAgent.investigator)
    assert_equal [ Ability::Invocation::DECISION_ALLOW, AbilityGateway::SOURCE_INVESTIGATION ], [ entry.decision, entry.source ]
    assert entry.completed_at
  end

  test "once an admin revokes the investigator's memory grant a run saves and disputes nothing, says why, and the refusal is logged" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)
    disputed = Chat::Memory.create!(workspace: @workspace, text: "Checkout runs in Dublin", state: Chat::Memory::STATE_UNCONFIRMED)
    @workspace.ability_grants.where(principal: SystemAgent.investigator, action: Ability::Action.where(key: %w[memory.create memory.update])).destroy_all

    assert_equal "Not allowed: this agent has no grant for memory.create in this workspace.",
                 Chat::Tools::Remember.new(investigation).call("fact" => "Checkout runs in Frankfurt")
    assert_equal "Not allowed: this agent has no grant for memory.update in this workspace.",
                 Chat::Tools::DisputeMemory.new(investigation).call("memory" => disputed.id, "reason" => "The deploy log shows Frankfurt")

    assert_nil Chat::Memory.find_by(workspace: @workspace, text: "Checkout runs in Frankfurt")
    assert_equal Chat::Memory::STATE_UNCONFIRMED, disputed.reload.state
    assert_equal [ Ability::Invocation::DECISION_DENY ] * 2,
                 @workspace.ability_invocations.where(principal: SystemAgent.investigator, action_key: %w[memory.create memory.update]).pluck(:decision)
  end

  test "a rehearsal reads memory, but is never offered a way to change it and never counts a use" do
    rehearsal = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
                                                  max_turns: 10, max_spend_cents: 400)
    memory = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)

    assert_equal [ Chat::Tools::Recall ], Chat::Tools.memory(rehearsal).map(&:class)
    assert_match "Deploys happen from main", Chat::Tools::Recall.new(rehearsal).call("words" => "deploys")
    assert_equal 0, memory.reload.use_count
    assert_equal [ Chat::Tools::Remember, Chat::Tools::Recall, Chat::Tools::DisputeMemory ], Chat::Tools.memory(@turn).map(&:class)
  end

  test "anything that looks like a secret is never remembered" do
    answer = Chat::Tools::Remember.new(@turn).call("fact" => "Prod is postgres://app:hunter2@db.internal:5432/app")

    assert_match "looks like it holds a secret (credential url)", answer
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

  test "the memories a chat starts with count as used once for the chat, not once per question" do
    memory = Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)

    2.times { Conversation::Runner.new(@conversation, asker: @member).send(:context) }

    assert_equal 1, memory.reload.use_count
  end

  test "a memory tool that did nothing marks its call failed, a missing memory as not found, and already remembered is no failure" do
    rejected = Chat::Memory.create!(workspace: @workspace, text: "Checkout uses MySQL", state: Chat::Memory::STATE_REJECTED)
    Chat::Memory.create!(workspace: @workspace, text: "Deploys happen from main", state: Chat::Memory::STATE_UNCONFIRMED)

    called(Chat::Tools::Remember, "remember_1", "fact" => "Ledger is slow", "about" => "ledger")
    called(Chat::Tools::Remember, "remember_2", "fact" => "Checkout currently runs 3 replicas")
    called(Chat::Tools::Remember, "remember_3", "fact" => "Checkout uses MySQL")
    secret = called(Chat::Tools::Remember, "remember_4", "fact" => "Prod is postgres://app:hunter2@db.internal:5432/app")
    called(Chat::Tools::Remember, "remember_5", "fact" => "deploys happen from main")
    called(Chat::Tools::CorrectMemory, "correct_1", "memory" => "nothing", "reason" => "wrong")
    called(Chat::Tools::CorrectMemory, "correct_2", "memory" => rejected.id, "reason" => "wrong")
    called(Chat::Tools::DisputeMemory, "dispute_1", "memory" => "nothing", "reason" => "wrong")
    called(Chat::Tools::DisputeMemory, "dispute_2", "memory" => rejected.id, "reason" => "wrong")

    assert_kind_of String, secret
    assert_match "looks like it holds a secret", secret
    chat = @conversation.chat_record
    failed = %w[remember_1 remember_2 remember_3 remember_4 correct_2 dispute_2].map { |id| chat.outcome_call(id).failure_kind }
    assert_equal [ Chat::StepOutcome::FAILURE_ERROR ] * 6, failed
    assert_equal [ Chat::StepOutcome::FAILURE_NOT_FOUND ] * 2, %w[correct_1 dispute_1].map { |id| chat.outcome_call(id).failure_kind }
    assert_not chat.outcome_call("remember_5").failed
  end

  test "a fact that contradicts a memory in a dashboard chat disputes it, asks there at once with where it came from, and tells Halon" do
    old = Chat::Memory.create!(workspace: @workspace, text: "web deploys from main", state: Chat::Memory::STATE_CONFIRMED, source: @conversation,
                               added_by: @member, confirmed_by: @member, confirmed_at: Time.current)
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([ FirefightAi::MemoryJudge::Verdict.new(id: old.id, verdict: FirefightAi::Schemas::MemoryVerdicts::CONTRADICTS) ])
    ConversationChannel.expects(:broadcast_to).with(@conversation, type: Conversation::LiveDelivery::EVENT_MEMORY)

    answer = Chat::Tools::Remember.new(@turn).call("fact" => "web deploys from the release branch", "seen_in" => "the deploy log of web")

    assert_match "It contradicts memory #{old.id}", answer
    assert_equal [ Chat::Memory::STATE_DISPUTED, "The deploy log of web shows \"web deploys from the release branch\"." ], old.reload.values_at(:state, :state_reason)
    card = @conversation.memory_posts.sole
    assert_equal [ [ old.id ], Chat::MemoryPost::KIND_DISPUTED, "The deploy log of web shows \"web deploys from the release branch\"." ],
                 [ card.memory_ids, card.kind, card.evidence ]
    shown = AgentChatMemoryQuestionSerializer.one(card, member: @member)
    assert_equal [ "your chat", "confirmed by you" ], shown.values_at(:origin, :trust)
  end

  test "a dispute from a live result in a dashboard chat asks there too, and one in a run asks only its incident's channel" do
    disputed = Chat::Memory.create!(workspace: @workspace, text: "Checkout runs in Frankfurt", state: Chat::Memory::STATE_UNCONFIRMED)
    ConversationChannel.expects(:broadcast_to).with(@conversation, type: Conversation::LiveDelivery::EVENT_MEMORY)

    Chat::Tools::DisputeMemory.new(@turn).call("memory" => disputed.id, "reason" => "The service's settings say Dublin.")

    assert_equal "The service's settings say Dublin.", @conversation.memory_posts.sole.evidence
  end

  private

  def memory(text) = Chat::Memory.where(workspace: @workspace).to_a.find { |each| each.text == text }

  def called(tool, id, **arguments)
    llm_call = RubyLLM::ToolCall.new(id: id, name: tool.tool_name, arguments: arguments)
    @conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => llm_call }))
    tool.new(@turn).call(tool_call: llm_call, **arguments.transform_keys(&:to_sym))
  end
end
