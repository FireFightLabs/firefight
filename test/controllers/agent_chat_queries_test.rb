require "test_helper"

# What opening a chat costs the database. The page and its conversation are two requests, and a longer chat must not
# cost more of either, since every message's steps and sources are read for the whole page at once.
class AgentChatQueriesTest < ActionDispatch::IntegrationTest
  NOT_COUNTED = %w[SCHEMA TRANSACTION].freeze
  FEW = 2
  MANY = 30
  # Pinned, so a query added per message or per prop shows here. Raise them only for a prop that is new.
  PAGE_QUERIES = 23
  THREAD_QUERIES = 36

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page a short chat opens on costs the pinned queries, and so does its conversation" do
    conversation = chat_with(FEW)

    assert_equal PAGE_QUERIES, counted { get agent_chat_url(conversation), headers: inertia_headers }.size
    assert_equal THREAD_QUERIES, counted { get agent_chat_url(conversation), headers: thread_headers }.size
  end

  test "a long chat costs the same queries as a short one, whatever its steps and replies" do
    conversation = chat_with(MANY)

    assert_equal PAGE_QUERIES, counted { get agent_chat_url(conversation), headers: inertia_headers }.size
    queries = counted { get agent_chat_url(conversation), headers: thread_headers }
    assert_equal THREAD_QUERIES, queries.size, repeated(queries)
  end

  test "the steps and sources a page shows are the same as each message read on its own" do
    conversation = chat_with(FEW)
    chat = conversation.chat
    Chat::Chart.record!(chat, "call_0_0", [ chart ])
    messages = chat.readable_messages.includes(:attached_files, :ruby_llm_usages, ruby_llm_tool_calls: :result).to_a

    together = AgentChatMessageSerializer.many(messages, member: @member, platform_texts: {})
    alone = messages.map { |message| AgentChatMessageSerializer.one(message, member: @member, platform_texts: {}) }

    assert_equal alone.as_json, together.as_json
    assert together.as_json.any? { |shown| shown["sources"].present? }
    assert together.as_json.flat_map { |shown| shown["tools"] }.any? { |step| step["card"].present? }
  end

  private

  def thread_headers = inertia_partial_headers("agent/index", AgentChatsController::THREAD_PROPS)

  # Each round is a question, a reply that reads twice, and the answer that ends the turn.
  def chat_with(rounds)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.ask!("Why is checkout slow?")
    chat = conversation.chat_record
    rounds.times do |round|
      chat.messages.create!(role: Chat::Message::ROLE_USER, content: "And now, #{round}?") if round.positive?
      asking = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
      2.times do |read|
        call = asking.ruby_llm_tool_calls.create!(tool_call_id: "call_#{round}_#{read}", name: Mcp::Tools::SEARCH_INCIDENTS, arguments: { "query" => "checkout" })
        call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "INC-#{round}#{read} https://example.com/incidents/#{round}#{read}"))
      end
      chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "Checkout is fine, #{round}.")
    end
    conversation.reply_delivered!
    conversation
  end

  def counted
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless NOT_COUNTED.include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    assert_response :success
    queries
  end

  def repeated(queries)
    queries.tally.select { |_sql, count| count > 1 }.map { |sql, count| "#{count}x #{sql.truncate(200)}" }.join("\n")
  end

  def chart
    { "title" => "5xx of checkout", "unit" => "count", "from" => 5.minutes.ago.iso8601, "to" => Time.current.iso8601,
      "series" => [ { "label" => "checkout", "points" => [ [ 5.minutes.ago.iso8601, 1 ], [ Time.current.iso8601, 2 ] ] } ] }
  end
end
