require "test_helper"

# Every answer lists what Halon read to give it, built from the turn's own calls and results, never from links the
# model wrote, compact and once each, in the dashboard, in a thread and on the bench.
class Chat::SourcesTest < ActiveSupport::TestCase
  RUN = "https://app.northflank.com/t/larkspur/project/shop/workflows/release/runs/4182".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
  end

  test "an answer lists the reads of its turn, each with the page its result gave, once each, never a change or a failed call" do
    asked!("how did the release go?", at: 10.minutes.ago)
    read!("old", Mcp::Tools::SEARCH_INCIDENTS, "INC-1 https://old.test/1", at: 9.minutes.ago)
    reply!("Earlier answer.", at: 8.minutes.ago)
    asked!("and now?", at: 5.minutes.ago)
    read!("c1", Mcp::Tools::GET_INCIDENT, "INC-160 API errors.\n#{Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: 'Firefight', url: 'https://app.firefight.app/incidents/INC-160'))}", at: 4.minutes.ago)
    read!("c2", Mcp::Tools::SEARCH_INCIDENTS, "Run 4182 failed at migrate. #{RUN}.", at: 3.minutes.ago)
    read!("c3", Mcp::Tools::SEARCH_INCIDENTS, "Run 4182 failed at migrate. #{RUN}.", at: 3.minutes.ago)
    read!("c4", Mcp::Tools::RESOLVE_INCIDENT, "Resolved INC-160 https://x.test/resolved", at: 2.minutes.ago)
    read!("c5", Mcp::Tools::GET_INCIDENT, "boom https://x.test/failed", at: 2.minutes.ago, failed: true)
    reply = reply!("Run 4182 failed.", at: 1.minute.ago)

    sources = Chat::Sources.for_reply(reply)

    assert_equal [ "https://app.firefight.app/incidents/INC-160", RUN ], sources.map(&:url)
    assert(sources.all? { |source| source.title.present? })
  end

  test "what a specialist read for the turn is listed with Halon's own reads, and asking it is not a source itself" do
    asked!("who holds the connections?", at: 3.minutes.ago)
    read!("call_ask", Chat::Tools::AskSpecialist::NAME, "Specialists reported, 1 of 1:", at: 2.minutes.ago)
    helper = Chat::Helper.start!(chat: @chat, tool_call_id: "call_ask", since: 3.minutes.ago,
                                 checks: [ Chat::Helpers::Check.new(title: "Databases", brief: "Read", deep: false, domain: Chat::Specialists::DATABASES) ]).sole
    own = Chat.open!(owner: helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o-mini"))
    read!("s_1", Mcp::Tools::SEARCH_INCIDENTS, "498 of 500 https://app.planetscale.com/x/insights", at: 2.minutes.ago, chat: own)
    reply = reply!("worker holds them.", at: 1.minute.ago)

    assert_equal [ "https://app.planetscale.com/x/insights" ], Chat::Sources.for_reply(reply).map(&:url)
  end

  test "the page ships the sources with the reply that ends a turn, and a thread gets them as one small line under the answer" do
    asked!("how did the release go?", at: 3.minutes.ago)
    read!("c1", Mcp::Tools::SEARCH_INCIDENTS, "Run 4182 failed. #{RUN}", at: 2.minutes.ago)
    reply = reply!("Run 4182 failed.", at: 1.minute.ago)

    shipped = AgentChatMessageSerializer.one(reply)[:sources]
    assert_equal [ RUN ], shipped.map { |source| source[:url] }

    blocks = Slack::Messages::AgentSources.build(Chat::Sources.for_reply(reply))
    assert_equal 1, blocks.size
    assert_equal "context", blocks.sole[:type]
    assert_match(/\ARead: <#{Regexp.escape(RUN)}\|.+>\z/, blocks.sole[:elements].sole[:text])
    assert_empty Slack::Messages::AgentSources.build([])
  end

  test "a streamed answer keeps its text and gets the sources line at its bottom, and one posted whole gets both" do
    adapter = Slack::WorkspaceAdapter.new(@workspace)
    adapter.stubs(:clear_agent_session)
    sources = [ Chat::Sources::Source.new(title: "Search logs web", url: RUN) ]
    Slack::Client.expects(:stop_stream).with { |arguments| arguments[:blocks].sole[:type] == "context" }.returns({ ts: "1.3" })
    adapter.post_agent_reply(channel_id: "C1", thread_id: "1.2", answer_id: "1.3", text: "Done.", streamed: true, sources: sources)

    Slack::Client.expects(:post_message).with { |arguments| arguments[:blocks].map { |block| block[:type] } == %w[section context] }.returns({ ts: "1.4" })
    adapter.post_agent_reply(channel_id: "C1", thread_id: "1.2", answer_id: nil, text: "Done.", sources: sources)
  end

  private

  def asked!(words, at:) = @chat.messages.create!(role: Chat::Message::ROLE_USER, content: words, created_at: at)

  def reply!(words, at:) = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: words, created_at: at)

  def read!(tool_call_id, name, answer, at:, failed: false, chat: @chat)
    message = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "", created_at: at)
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: {}, failed: failed)
    call.update!(result: chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer, created_at: at))
  end
end
