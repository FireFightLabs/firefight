require "test_helper"

# What opening a chat costs the database. The page and its conversation are two requests, and a longer chat must not
# cost more of either, since every message's steps and sources are read for the whole page at once.
class AgentChatQueriesTest < ActionDispatch::IntegrationTest
  NOT_COUNTED = %w[SCHEMA TRANSACTION].freeze
  FEW = 2
  MANY = 30
  # Pinned, so a query added per message or per prop shows here. Raise them only for a prop that is new. The
  # conversation is counted before the tools' labels are cached (Workspace::ToolLabels), so it reads them, and once they
  # are it sends one query fewer.
  PAGE_QUERIES = 18
  THREAD_QUERIES = 46
  # What a question sent from the open chat reads back. Nothing the page shares is counted, since none of it is sent.
  ASKED_QUERIES = 27

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    # Cached as in production, so the tools' labels a page reads once are read from the cache after.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
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

  test "a question sent from the open chat reads back the pinned queries, however long the chat" do
    [ chat_with(FEW), chat_with(MANY) ].each do |conversation|
      oldest = conversation.chat.readable_messages.first
      headers = inertia_partial_headers("agent/index", AgentChatsController::ASKED_PROPS)
                .merge("X-Inertia-Reset" => AgentChatsController::PROP_MESSAGES, AgentChatsController::LOADED_FROM_HEADER => oldest.id)

      # A request reads its workspace afresh, so the tools' labels it memoizes are read again.
      sign_in(users(:alice), Workspace.find(@workspace.id))
      Rails.cache.clear
      queries = counted { get agent_chat_url(conversation), headers: headers }

      assert_equal ASKED_QUERIES, queries.size, repeated(queries)
    end
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

  test "a list reads each chat's newest readable message and first question as each chat reads its own, without what only a turn reads" do
    empty = Conversation.start_personal!(workspace: @workspace, member: @member).tap(&:chat_record)
    conversations = [ chat_with(FEW), chat_with(1), empty ]

    listed = Conversation.with_previews(Conversation.where(id: conversations.map(&:id)))

    listed.each do |conversation|
      alone = Chat.find_by!(owner: conversation)
      assert_equal [ alone.last_readable_message, alone.first_question ], [ conversation.chat.last_readable_message, conversation.chat.first_question ]
    end
    assert_not listed.first.chat.has_attribute?(:connections_seen)
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
        call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer(chat, round, read)))
      end
      chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "Checkout is fine, #{round}.")
    end
    conversation.reply_delivered!
    conversation
  end

  # The second read of each round was too large to hand over, so its answer names where it was kept whole.
  def answer(chat, round, read)
    return "INC-#{round}#{read} https://example.com/incidents/#{round}#{read}" if read.zero?

    kept = chat.saved_results.keep!(tool_name: Mcp::Tools::SEARCH_INCIDENTS, text: "INC-#{round}#{read}\n" * 50)
    "[Too large to hand over, saved as #{kept.handle}. Read it with read_result.]"
  end

  # Each request starts with an empty query cache, as it does in production, so a query the request before made is still
  # counted.
  def counted
    ActiveRecord::Base.lease_connection.clear_query_cache
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
