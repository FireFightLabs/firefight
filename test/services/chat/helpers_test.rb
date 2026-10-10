require "test_helper"

# Halon hands independent checks to helpers that run at the same time, each reading as whoever the chat or run acts for,
# spending from the same budget, and reporting back in a few lines.
class Chat::HelpersTest < ActiveSupport::TestCase
  ANSWERED = FirefightAi::AgentLoop::STATUS_ANSWERED

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @chat = @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @bob)
    @purse = FirefightAi::AgentLoop::Purse.new
    @moved = 0
    @model = FirefightAi::ModelChoice.new(model: "gpt-4o")
    @side = FirefightAi::ModelChoice.new(model: "gpt-4o-mini")
  end

  test "every check runs at the same time on a chat of its own, and the asking loop reads each report in order" do
    together = Concurrent::CountDownLatch.new(3)
    threads = Concurrent::Set.new
    FirefightAi::Helper.any_instance.stubs(:run).with do |chat:, **|
      threads << Thread.current
      together.count_down
      # Each waits for the others, so this only passes when all three run at once.
      assert together.wait(5), "the helpers did not run at the same time"
      chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "Read #{chat.owner.title}.")
      true
    end.returns(outcome(spent_micros: 20_000))

    result = hand_off(checks("Logs of web", "Recent deploys", "Error rate"))

    assert_not result.failed
    assert_equal [ "Helpers reported, 3 of 3:", "- Logs of web: Read Logs of web.", "- Recent deploys: Read Recent deploys.", "- Error rate: Read Error rate." ],
                 result.text.lines.map(&:chomp)
    assert_equal 3, threads.size
    helpers = @chat.helpers.to_a
    assert_equal [ Chat::Helper::STATUS_REPORTED ] * 3, helpers.map(&:status)
    assert helpers.all? { |helper| helper.own_chat.messages.first.content.start_with?("Your check: #{helper.title}") }
    assert_operator @moved, :>=, 2
  end

  test "what helpers spend comes out of the asking loop's purse, and each is given a share of what is left" do
    shares = Concurrent::Array.new
    FirefightAi::Helper.any_instance.stubs(:run).with do |chat:, max_spend_cents:, **|
      shares << max_spend_cents
      chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "Nothing new in the logs.")
      true
    end.returns(outcome(spent_micros: 30_000))
    @purse.add(1_000_000)

    hand_off(checks("Logs", "Deploys"), max_spend_cents: 400)

    # 300 cents left, split three ways, one part kept for Halon itself.
    assert_equal [ 100, 100 ], shares.to_a
    assert_equal 1_060_000, @purse.spent
    assert_equal [ 30_000, 30_000 ], @chat.helpers.map(&:spent_micros)
  end

  test "a quick check runs on the side jobs' model and a deep one on the main model" do
    models = Concurrent::Hash.new
    FirefightAi::Helper.any_instance.stubs(:run).with do |chat:, **|
      models[chat.owner.title] = chat.model_id
      chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "Done.")
      true
    end.returns(outcome)

    hand_off([ Chat::Helpers::Check.new(title: "Logs", brief: "Read the logs", deep: false),
          Chat::Helpers::Check.new(title: "Code", brief: "Read the handler", deep: true) ])

    assert_equal({ "Logs" => "gpt-4o-mini", "Code" => "gpt-4o" }, models.to_h)
    assert_equal [ "gpt-4o-mini", "gpt-4o" ], @chat.helpers.map(&:model)
  end

  test "a helper that fails or runs dry says why, and never takes the others with it" do
    FirefightAi::Helper.any_instance.stubs(:run).with do |chat:, **|
      raise FirefightAi::TransientError, "provider down" if chat.owner.title == "Logs"

      true
    end.returns(outcome(status: FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET))

    result = hand_off(checks("Logs", "Deploys"))

    assert result.failed
    assert_equal [ "- Logs: #{Chat::Helper::COULD_NOT}", "- Deploys: #{Chat::Helper::OUT_OF_BUDGET}" ], result.text.lines.drop(1).map(&:chomp)
    assert_equal [ Chat::Helper::STATUS_FAILED ] * 2, @chat.helpers.map(&:status)
  end

  test "a person's stop reaches every helper, and each ends as stopped" do
    FirefightAi::Helper.any_instance.stubs(:run).with { |canceled:, **| canceled.call }.returns(outcome(status: FirefightAi::AgentLoop::STATUS_CANCELED))

    hand_off(checks("Logs"), canceled: -> { true })

    assert_equal [ [ Chat::Helper::STATUS_STOPPED, Chat::Helper::STOPPED ] ], @chat.helpers.map { |helper| [ helper.status, helper.ended_because ] }
  end

  test "with too little budget left nothing is handed off, and Halon is told to read it itself" do
    FirefightAi::Helper.any_instance.expects(:run).never
    @purse.add(399 * FirefightAi::AgentLoop::MICROS_PER_CENT)

    result = hand_off(checks("Logs"), max_spend_cents: 400)

    assert result.failed
    assert_equal Chat::Helpers::NO_BUDGET, result.text
    assert_empty @chat.helpers
  end

  test "a helper reads as the person who asked, through the chat's own source, and is never offered a change" do
    faylee = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Faylee", slug: "faylee",
                                             settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    faylee.integration_environments.create!
    purge = faylee.tools.create!(name: "purge_cache", description: "Purge the cache", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: purge.ability_action)
    helper = Chat::Helper.start!(chat: @chat, tool_call_id: "call_1", checks: checks("Logs"), since: 1.minute.ago).sole
    agent = Chat::Helpers::Agent.new(helper, parent: @turn)
    Chat::ToolCall.expects(:run!).with do |principal:, context:, **|
      principal == @bob && context[:source] == AbilityGateway::SOURCE_CONVERSATION
    end.returns("ok")

    assert_equal "ok", agent.tool_call(action_key: "incidents.read").value
    assert_equal Chat::Tools::STATE_READS_ONLY, Chat::Tools.catalog(agent).find { |entry| entry.name == "faylee_purge_cache" }.state
    assert_not agent.confirms?(purge.ability_action)
    assert_equal [ @chat, "call_1" ], agent.charts_kept_on("h_1"), "a chart a helper reads is drawn under the step that started it"
  end

  test "in a run, every read a helper makes is a numbered step of the run, as the investigator, so the answer can cite it" do
    incident = incidents(:active_critical_ws1)
    investigation = @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    chat = investigation.chat_record(@model)
    helper = Chat::Helper.start!(chat: chat, tool_call_id: "call_1", checks: checks("Logs"), since: investigation.created_at).sole
    Chat::ToolCall.expects(:run!).with { |principal:, **| principal == SystemAgent.investigator }.returns("3 errors")

    said = Chat::Helpers::Agent.new(helper, parent: Investigation.find(investigation.id)).tool_call(action_key: "incidents.read", tool_name: "get_incident")

    assert_equal [ "3 errors", 1 ], [ said.value, said.step ]
    assert_equal Investigation::Step::STATUS_SUCCEEDED, investigation.steps.find_by!(position: 1).status
  end

  private

  def checks(*titles) = titles.map { |title| Chat::Helpers::Check.new(title: title, brief: "Read #{title}", deep: false) }

  def outcome(status: ANSWERED, spent_micros: 0) = FirefightAi::AgentLoop::Outcome.new(status: status, turns_used: 2, spent_micros: spent_micros)

  def hand_off(checks, max_spend_cents: 400, canceled: -> { false })
    conversation = @conversation
    bob = @bob
    share = Chat::Helpers::Share.new(
      purse: @purse, max_spend_cents: max_spend_cents, since: 1.minute.ago, canceled: canceled, moved: -> { @moved += 1 },
      fresh_parent: -> { Conversation::Turn.new(Conversation.find(conversation.id), asker: bob) }, choose: ->(deep) { deep ? @model : @side },
      inferable: conversation, member: bob
    )
    Chat::Helpers.run!(@turn, share: share, tool_call_id: "call_1", checks: checks)
  end
end
