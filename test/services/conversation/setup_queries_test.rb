require "test_helper"

# Getting a chat's turn ready is mostly round trips to the database, which across a network cost seconds before the model
# starts. A workspace with a real one's connections is read in a bounded number of queries, whoever asks, and the tool
# catalogue is built once per turn.
class Conversation::SetupQueriesTest < ActiveSupport::TestCase
  # What a turn's setup sends today is about 65 queries for an owner and 75 for a member, from about 95 and 405 before the
  # catalogue was shared and its reads batched. The ceilings leave room for a new note without letting a loop back in.
  OWNER_CEILING = 80
  MEMBER_CEILING = 90
  # What a whole reply of this workspace sends, with the query cache off so a read repeated after a write counts. It was
  # 153 before the reads a reply repeats were held.
  REPLY_CEILING = 152

  setup do
    @workspace = workspaces(:slack_workspace_one)
    stub_post_message
    stub_agent_session
    FirefightAi.configuration.stubs(:specialists).returns(FirefightAi::Configuration::SPECIALISTS_AUTO)
    FirefightAi.stubs(:tool_search?).returns(false)
  end

  test "a turn's setup for a member of a workspace with many connections stays within a ceiling" do
    connect_big_workspace!

    assert_operator setup_queries(workspace_memberships(:bob_workspace_one)), :<=, MEMBER_CEILING
  end

  test "a turn's setup for an owner of a workspace with many connections stays within a ceiling" do
    connect_big_workspace!

    assert_operator setup_queries(workspace_memberships(:alice_workspace_one)), :<=, OWNER_CEILING
  end

  test "the tool catalogue is built once while a turn gets ready, and again for the next turn" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    answer_with_fake(conversation)
    Chat::Tools.expects(:build_catalog).twice.returns([])
    Chat::Specialists.expects(:crowded?).twice.returns(false)

    2.times do |each|
      conversation.ask!("question #{each}")
      Conversation::Runner.new(conversation, asker: conversation.started_by).run
    end
  end

  test "deciding whether to ask specialists sums the tools' stored lengths and never builds the catalogue" do
    connect_big_workspace!
    turn = turn_for(workspace_memberships(:bob_workspace_one))
    Chat::Tools.expects(:build_catalog).never

    sent = sql_of { Chat::Specialists.crowded?(turn) }

    tool_reads = sent.grep(/FROM "integration_tools"/)
    assert_equal 1, tool_reads.size
    assert_includes tool_reads.sole, '"integration_tools"."definition_chars"'
    assert(sent.none? { |sql| sql.match?(/integration_environments|params_schema|"integration_tools"\.\*/) },
           "no schema or environment is read for the decision")
  end

  test "deciding whether to ask specialists reads only the columns of each action and connection it uses" do
    connect_big_workspace!
    turn = turn_for(workspace_memberships(:bob_workspace_one))

    sent = sql_of { Chat::Specialists.crowded?(turn) }

    actions = sent.grep(/FROM "ability_actions" WHERE "ability_actions"."source_type"/)
    assert_equal 1, actions.size
    assert_equal Chat::Specialists::ACTION_COLUMNS.map(&:to_s), actions.sole[/\ASELECT (.+?) FROM/, 1].scan(/"ability_actions"\."(\w+)"/).flatten
    connections = sent.grep(/FROM "integrations" WHERE "integrations"."id" IN/)
    assert_equal 1, connections.size
    assert_equal Chat::Specialists::INTEGRATION_COLUMNS.map(&:to_s), connections.sole[/\ASELECT (.+?) FROM/, 1].scan(/"integrations"\."(\w+)"/).flatten
    assert(sent.none? { |sql| sql.match?(/"ability_actions"\.\*|"integrations"\.\*/) }, "no action or connection is read whole")
  end

  test "deciding whether to ask specialists answers as it did when the actions and connections were read whole" do
    connect_big_workspace!
    [ :bob_workspace_one, :alice_workspace_one ].each do |fixture|
      member = workspace_memberships(fixture)
      [ false, true ].each do |reads_only|
        turn = Conversation::Turn.new(turn_for(member).conversation, asker: member, reads_only: reads_only)
        length = tail_length(turn)
        [ length / FirefightAi::TOOL_CHARS_PER_TOKEN, length / FirefightAi::TOOL_CHARS_PER_TOKEN - 1, 0, 10_000_000 ].each do |budget|
          FirefightAi.configuration.stubs(:held_tools_budget).returns(budget)

          assert_equal crowded_with_whole_rows?(turn), Chat::Specialists.crowded?(turn), "#{fixture}, reads only #{reads_only}, budget #{budget}"
        end
      end
    end
  end

  test "a reply reads the workspace's model overrides, AI accounts and connection lists once while it gets ready" do
    connect_big_workspace!
    @workspace.ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "gpt-4o", provider: "openai")
    add_ai_account!(@workspace, provider: "openai", key: "sk-own-openai")
    owner = workspace_memberships(:alice_workspace_one)

    sent = reply_queries(owner)
    counted = ->(table) { sent.count { |sql| sql.match?(/FROM "#{table}"/) } }

    assert_equal 1, counted.call("ai_model_overrides"), repeated_queries(sent)
    assert_equal 1, counted.call("workspace_ai_accounts"), repeated_queries(sent)
    assert_equal 1, sent.count { |sql| sql.match?(/FROM "integrations" WHERE "integrations"."workspace_id" = \$1 AND "integrations"."deleted_at" IS NULL ORDER BY "integrations"."name"/) }
    assert_equal 1, sent.count { |sql| sql.match?(/FROM "integrations" WHERE "integrations"."workspace_id" = \$1 AND "integrations"."provider" != \$2 AND "integrations"."disabled_at" IS NULL/) }
    assert_operator sent.size, :<=, REPLY_CEILING, repeated_queries(sent)
  end

  test "a reply reads the AI accounts again once the model works, so an account that ran dry is skipped" do
    first = add_ai_account!(@workspace, provider: "openai", key: "sk-own-first", label: "First")
    second = add_ai_account!(@workspace, provider: "openai", key: "sk-own-second", label: "Second")
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    seen = []
    responder = Object.new
    workspace = nil
    responder.define_singleton_method(:run) do |**|
      workspace = conversation.workspace
      seen << workspace.usable_ai_accounts.map(&:id)
      first.ran_out!(StandardError.new("out of credit"))
      seen << workspace.usable_ai_accounts.map(&:id)
      conversation.reload.chat.add_message(role: :assistant, content: "Hi.")
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    end
    responder.define_singleton_method(:ai_model) { FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil) }
    FirefightAi::Responder.stubs(:new).returns(responder)
    conversation.ask!("hey")

    Conversation::Runner.new(conversation, asker: conversation.started_by).run

    assert_equal [ [ first.id, second.id ], [ second.id ] ], seen
    assert_equal [ first.id, second.id ].sort, workspace.workspace_ai_accounts.pluck(:id).sort
  end

  test "a member and an owner in the same workspace each count the tools the catalogue hands them ready to call" do
    connect_big_workspace!
    member = turn_for(workspace_memberships(:bob_workspace_one))
    owner = turn_for(workspace_memberships(:alice_workspace_one))
    member_length = tail_length(member)
    owner_length = tail_length(owner)
    assert_operator member_length, :<, owner_length, "a member holds no grant for the changes an owner may make"

    FirefightAi.configuration.stubs(:held_tools_budget).returns((member_length / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil)
    assert_not Chat::Specialists.crowded?(member), "the changes a member cannot call are not counted against them"
    assert Chat::Specialists.crowded?(owner)
  end

  test "a tool's stored length is what fits_up_front? measures of the tool a turn is handed" do
    connect_big_workspace!
    alice = workspace_memberships(:alice_workspace_one)
    turn = Conversation::Turn.new(turn_for(alice).conversation, asker: alice, reads_only: true)
    handed = Chat::Tools.build_catalog(turn).select { |entry| entry.tool.is_a?(Chat::Tools::Connection) }.map(&:tool)
    stored = Integration::Tool.in_workspace(@workspace).index_by(&:model_facing_name)
    reads = handed.select { |tool| stored[tool.name].read_only? && Integrations::ReadGuards.for(stored[tool.name]).nil? }
    assert_operator reads.size, :>, 10

    measured = reads.sum { |tool| tool.name.size + tool.description.size + tool.parameters_schema.to_json.size }
    assert_equal measured, reads.sum { |tool| stored[tool.name].definition_chars }

    FirefightAi.configuration.stubs(:held_tools_budget).returns((measured / FirefightAi::TOOL_CHARS_PER_TOKEN).floor)
    assert_equal FirefightAi.fits_up_front?(reads), FirefightAi.chars_fit_up_front?(measured)
    FirefightAi.configuration.stubs(:held_tools_budget).returns((measured / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil)
    assert_equal FirefightAi.fits_up_front?(reads), FirefightAi.chars_fit_up_front?(measured)
  end

  test "deciding whether to ask specialists answers as the tools' definitions measured whole would" do
    connect_big_workspace!
    turn = turn_for(workspace_memberships(:alice_workspace_one))
    length = tail_length(turn)

    FirefightAi.configuration.stubs(:held_tools_budget).returns((length / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil)
    assert_not Chat::Specialists.crowded?(turn), "tools that fit the budget exactly keep today's way"

    FirefightAi.configuration.stubs(:held_tools_budget).returns((length / FirefightAi::TOOL_CHARS_PER_TOKEN).floor - 1)
    assert Chat::Specialists.crowded?(turn), "past the budget, with reads a specialist takes, it asks specialists"

    Integration::Tool.switched_on_in(@workspace).update_all(read_only: false)
    assert_not Chat::Specialists.crowded?(turn), "with no read a specialist would take, it keeps today's way however many tools"
  end

  test "deciding whether to ask specialists counts only the connection tools the catalogue hands the turn as its own" do
    connect_big_workspace!
    turn = turn_for(workspace_memberships(:alice_workspace_one))
    everything = Integration::Tool.switched_on_in(@workspace).sum(:definition_chars)
    length = tail_length(turn)
    assert_operator length, :<, everything, "a capability's tools are reached through it and not counted"

    FirefightAi.configuration.stubs(:held_tools_budget).returns((length / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil)
    assert_not Chat::Specialists.crowded?(turn)

    reading = Conversation::Turn.new(turn.conversation, asker: turn.asker, reads_only: true)
    reads_length = tail_length(reading)
    assert_operator reads_length, :<, length, "a turn that only reads is never handed a change"
    FirefightAi.configuration.stubs(:held_tools_budget).returns((reads_length / FirefightAi::TOOL_CHARS_PER_TOKEN).ceil)
    assert_not Chat::Specialists.crowded?(reading)
    assert Chat::Specialists.crowded?(turn)
  end

  test "comparing connections reads only the tool columns it compares" do
    connect_big_workspace!(sources: 2)

    tool_queries = sql_of { Chat::Tools::Changes.snapshot(@workspace) }.grep(/FROM "integration_tools"/)

    assert_equal 1, tool_queries.size
    selected = tool_queries.sole[/\ASELECT (.+?) FROM/, 1]
    assert_equal %w[id integration_id name enabled removed_at], selected.scan(/"integration_tools"\."(\w+)"/).flatten
    assert_no_match(/\*/, selected)
  end

  test "comparing connections still sees each connection's switched on tools by the name the agent calls them" do
    connect_big_workspace!(sources: 1)
    integration = @workspace.integrations.connections.where(deleted_at: nil).sole
    integration.tools.order(:name).first.update!(enabled: false)
    expected = integration.tools.reload.select { |tool| tool.enabled? && tool.available? }.map(&:model_facing_name).sort

    assert_equal expected, Chat::Tools::Changes.snapshot(@workspace).dig(integration.id.to_s, "tools")
  end

  test "comparing connections reads the same few queries however many there are" do
    connect_big_workspace!(sources: 1)
    few = queries_of { Chat::Tools::Changes.snapshot(@workspace) }
    connect_big_workspace!

    assert_equal few, queries_of { Chat::Tools::Changes.snapshot(@workspace) }
  end

  test "what each connection reaches reads the same when the map's accounts are read for all of them at once" do
    connect_big_workspace!(sources: 3)
    @workspace.integrations.where(deleted_at: nil).each_with_index do |integration, index|
      row = integration.integration_environments.first
      %w[zeta/web Alpha/api beta/db mid/queue omega/cron].rotate(index).first(index + 2).each do |account|
        ResourceMap::Resource.create!(workspace: @workspace, provider: integration.provider, account: account, kind: ResourceMap::KIND_SERVICE,
                                      external_id: "#{integration.slug}-#{account}", name: account, integration_environment: row,
                                      first_seen_at: 1.day.ago, last_seen_at: Time.current)
      end
    end
    one_by_one = @workspace.integrations.where(deleted_at: nil).includes(:integration_environments).order(:created_at).map(&:reach)
    together = Integration.with_mapped_accounts(@workspace.integrations.where(deleted_at: nil).includes(:integration_environments).order(:created_at).to_a).map(&:reach)

    assert_equal one_by_one, together
    assert(together.all? { |reach| reach.to_s.start_with?("account") })
  end

  private

  # Every provider the bench's large workspace names, as connections with its tools switched on.
  def connect_big_workspace!(sources: nil)
    grouped = YAML.safe_load_file(Conversation::BenchWorkspace::TOOLS).group_by { |tool| tool["source"] }
    grouped.first(sources || grouped.size).each do |source, tools|
      next if @workspace.integrations.exists?(slug: source)

      entry = IntegrationProvider.find(source)
      integration = @workspace.integrations.create!(kind: entry.kind, provider: source, name: entry.name, slug: source,
                                                    settings: { "server_url" => "https://mcp.example.com/#{source}" })
      integration.integration_environments.create!(credentials: { token: "x" }.to_json)
      tools.each do |tool|
        integration.tools.create!(name: tool["name"].delete_prefix("#{source}_"), description: tool["description"], read_only: tool["reads"] == true,
                                  enabled: true, params_schema: tool["parameters"] || { "type" => "object" })
      end
    end
  end

  # The queries the second turn's setup sent, by its own log, so the first turn's opening of the chat is left out.
  def setup_queries(member)
    conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    answer_with_fake(conversation)
    conversation.ask!("hey")
    Conversation::Runner.new(conversation, asker: member).run
    conversation.ask!("hey again")
    logged = []
    Rails.logger.stubs(:info).with { |line| logged << line }
    Conversation::Runner.new(Conversation.find(conversation.id), asker: WorkspaceMembership.find(member.id)).run
    steps = logged.grep(String).filter_map { |line| JSON.parse(line) if line.include?(Conversation::Runner::SETUP_STEP_EVENT) }
    assert_includes steps.map { |step| step["step"] }, Conversation::Runner::STEP_PRESENTED
    steps.sum { |step| step["queries"] }
  end

  # The statements the second reply sends before the answer, one for each read, since the query cache is off.
  def reply_queries(member)
    conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    answer_with_fake(conversation)
    conversation.ask!("hey")
    Conversation::Runner.new(conversation, asker: member).run
    conversation.ask!("hey again")
    reloaded = Conversation.find(conversation.id)
    answer_with_fake(reloaded)
    ActiveRecord::Base.uncached do
      queries_sent { Conversation::Runner.new(reloaded, asker: WorkspaceMembership.find(member.id)).run }
    end
  end

  def turn_for(member)
    Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: member), asker: member)
  end

  # How long the connection tools the catalogue hands the turn ready to call are, by the length each tool's row keeps.
  def tail_length(turn)
    names = Chat::Tools.build_catalog(turn).select { |entry| entry.tool && entry.source != Chat::Skill::SOURCE_FIREFIGHT }.map(&:name).to_set
    Integration::Tool.in_workspace(@workspace).select { |tool| names.include?(tool.model_facing_name) }.sum(&:definition_chars)
  end

  # What crowded? answered when it read each tool's connection and action whole.
  def crowded_with_whole_rows?(turn)
    principal = turn.acting_principal
    tools = Integration::Tool.switched_on_in(turn.workspace).select(:id, :integration_id, :name, :read_only, :definition_chars)
                             .preload(:integration, :ability_action).to_a
    reading = tools.select(&:read_only?).map(&:model_facing_name).to_set
    resolved = Chat::Tools.granted(turn)
    tail = tools.select do |tool|
      !Chat::Tools.through_capability?(tool) && !Chat::Tools.withheld_from?(turn, tool) && tool.callable_by?(principal, resolved)
    end
    tail.any? { |tool| Chat::Specialists.of_provider(tool.integration.provider).present? && reading.include?(tool.model_facing_name) } &&
      !FirefightAi.chars_fit_up_front?(tail.sum(&:definition_chars))
  end

  def sql_of(&) = queries_sent(transactions: true, &)

  def queries_of(&) = queries_sent(transactions: true, &).size

  def answer_with_fake(conversation)
    responder = Object.new
    responder.define_singleton_method(:run) do |**|
      conversation.reload.chat.add_message(role: :assistant, content: "Hi.")
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    end
    responder.define_singleton_method(:ai_model) { FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil) }
    FirefightAi::Responder.stubs(:new).returns(responder)
  end
end
