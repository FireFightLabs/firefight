require "test_helper"

# Getting a chat's turn ready is mostly round trips to the database, which across a network cost seconds before the model
# starts. A workspace with a real one's connections is read in a bounded number of queries, whoever asks, and the tool
# catalogue is built once per turn.
class Conversation::SetupQueriesTest < ActiveSupport::TestCase
  # What a turn's setup sends today is about 65 queries for an owner and 75 for a member, from about 95 and 405 before the
  # catalogue was shared and its reads batched. The ceilings leave room for a new note without letting a loop back in.
  OWNER_CEILING = 80
  MEMBER_CEILING = 90

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
    Chat::Specialists.expects(:crowded?).twice.with { |turn| Chat::Tools.catalog(turn) }.returns(false)

    2.times do |each|
      conversation.ask!("question #{each}")
      Conversation::Runner.new(conversation, asker: conversation.started_by).run
    end
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

  def queries_of(&)
    counted = Conversation::Runner::QueryCount.new
    counted.count(&)
    counted.total
  end

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
