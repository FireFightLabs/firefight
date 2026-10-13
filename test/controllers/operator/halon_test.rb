require "test_helper"

class Operator::HalonTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:alice)
    @previous = ENV[Operator::Credential::OPERATOR_IDS_ENV]
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @operator.id
    @workspace = workspaces(:slack_workspace_one)
    @run = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400,
      status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError", started_at: 2.minutes.ago, completed_at: 1.minute.ago
    )
    @step = @run.steps.create!(position: 1, tool_name: "github_show_commit", action_key: "github.show_commit",
                               status: Investigation::Step::STATUS_SUCCEEDED, started_at: 90.seconds.ago, completed_at: 80.seconds.ago,
                               raw_result: "diff --git a/config/pool.yml")
  end

  teardown do
    ENV[Operator::Credential::OPERATOR_IDS_ENV] = @previous
  end

  test "nobody but a verified operator reaches Halon's runs, traces or chats" do
    sign_in(users(:bob), @workspace)

    [ operator_root_path, operator_halon_path, operator_halon_run_path(@run), operator_halon_chats_path, operator_find_path(q: @run.id) ].each do |path|
      get path, headers: inertia_headers
      assert_response :not_found
    end
  end

  test "the overview puts a run that failed on our side at the top, opening its trace" do
    as_operator

    get operator_root_path, headers: inertia_headers

    item = inertia_props["attentionItems"].find { |candidate| candidate["key"] == "#{Operator::Attention::KIND_HALON_FAILED}-#{@run.id}" }
    assert_equal operator_halon_run_path(@run), item["href"]
    assert_nil inertia_props["jobs"], "the test database has no queue, which the page says rather than failing"
    assert_operator inertia_props["halon"]["failed"], :>=, 1
    assert_operator inertia_props["attention"], :>=, 1
  end

  test "runs and health read one workspace over the window asked for" do
    as_operator

    get operator_halon_path(workspace: @workspace.id, window: Operator::Filter::WINDOW_WEEK, ending: Operator::HalonRuns::ENDING_FAILED), headers: inertia_headers

    assert_equal({ "window" => Operator::Filter::WINDOW_WEEK, "workspace" => @workspace.id }, inertia_props["filter"])
    assert_includes 7..8, inertia_props["buckets"].size, "a bar a day, the first and last partial"
    assert inertia_props["runs"].any? { |row| row["id"] == @run.id && row["errorSummary"] == "Faraday::TimeoutError" }
  end

  test "a trace carries its spans without their content, and opening one reads it" do
    as_operator

    get operator_halon_run_path(@run), headers: inertia_headers
    span = inertia_props["groups"].sole["spans"].find { |candidate| candidate["key"] == "tool-#{@step.id}" }
    assert span["hasBody"]
    assert_not inertia_props.key?(Operator::Trace::BODY_PROP)
    assert_not_includes response.body, "config/pool.yml"

    get operator_halon_run_path(@run, Operator::Trace::SPAN_PARAM => span["key"]),
        headers: inertia_headers.merge("X-Inertia-Partial-Component" => "operator/halon/run", "X-Inertia-Partial-Data" => Operator::Trace::BODY_PROP)
    assert_match "config/pool.yml", inertia_props[Operator::Trace::BODY_PROP]
  end

  test "chats are listed, and one opens its turns" do
    as_operator
    conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    chat = @workspace.chats.create!(owner: conversation, model: "claude-sonnet-4-5", provider: :anthropic)
    chat.add_message(role: :user, content: "What changed today?")

    get operator_halon_chats_path, headers: inertia_headers
    assert inertia_props["chats"].any? { |row| row["id"] == conversation.id }

    get operator_halon_chat_path(conversation), headers: inertia_headers
    assert_equal 1, inertia_props["turns"]
  end

  test "a chat from Slack reads as Slack shows it in the list and the trace, and the trace shows what the model read on asking" do
    as_operator
    bob = workspace_memberships(:bob_workspace_one)
    written = "<@#{bob.platform_user_id}> says checkout is :fire:"
    read = "@#{bob.display_name} (#{bob.platform_user_id}) says checkout is 🔥"
    shown = "@#{bob.display_name} says checkout is 🔥"
    direct = Conversation.start_direct!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one), channel_id: "D0ALICE", thread_id: "1")
    direct.ask!(read, as_written: written)

    get operator_halon_chats_path, headers: inertia_headers
    assert_equal shown, inertia_props["chats"].find { |row| row["id"] == direct.id }["title"]

    get operator_halon_chat_path(direct), headers: inertia_headers
    asked = inertia_props["groups"].sole["spans"].find { |span| span["kind"] == Operator::Trace::KIND_ASK }
    assert_equal shown, asked["detail"]
    assert asked["readByModel"]

    partial = inertia_headers.merge("X-Inertia-Partial-Component" => "operator/halon/chat", "X-Inertia-Partial-Data" => Operator::Trace::BODY_PROP)
    get operator_halon_chat_path(direct, Operator::Trace::SPAN_PARAM => asked["key"]), headers: partial
    assert_equal shown, inertia_props[Operator::Trace::BODY_PROP]

    get operator_halon_chat_path(direct, Operator::Trace::SPAN_PARAM => asked["key"], Operator::Trace::MODEL_PARAM => "1"), headers: partial
    assert_equal read, inertia_props[Operator::Trace::BODY_PROP]
  end

  test "a run asked for in Slack is named as Slack shows it in the list, the trace and the finder, and its facts show what the model read" do
    as_operator
    bob = workspace_memberships(:bob_workspace_one)
    written = "<@#{bob.platform_user_id}> says checkout is :fire:"
    read = "@#{bob.display_name} (#{bob.platform_user_id}) says checkout is 🔥"
    shown = "@#{bob.display_name} says checkout is 🔥"
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 20, max_spend_cents: 400, status: Investigation::STATUS_FAILED,
      error_summary: "Faraday::TimeoutError", started_at: 2.minutes.ago, completed_at: 1.minute.ago,
      brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => written, Investigation::Brief::KEY_SYMPTOM_FOR_MODEL => read },
                                       source: Investigation::Brief::SOURCE_COMMAND)
    )
    run.update!(seed_pack: Investigation::QuestionSeed.new(run).gather)

    get operator_halon_path, headers: inertia_headers
    assert_equal shown, inertia_props["runs"].find { |row| row["id"] == run.id }["label"]

    get operator_halon_run_path(run), headers: inertia_headers
    facts = inertia_props["groups"].sole["spans"].find { |span| span["key"] == "facts" }
    assert_equal shown, facts["facts"].find { |fact| fact["label"] == "Question" }["value"]
    assert facts["readByModel"]

    partial = inertia_headers.merge("X-Inertia-Partial-Component" => "operator/halon/run", "X-Inertia-Partial-Data" => Operator::Trace::BODY_PROP)
    get operator_halon_run_path(run, Operator::Trace::SPAN_PARAM => "facts"), headers: partial
    assert_includes inertia_props[Operator::Trace::BODY_PROP], shown
    assert_not_includes inertia_props[Operator::Trace::BODY_PROP], read

    get operator_halon_run_path(run, Operator::Trace::SPAN_PARAM => "facts", Operator::Trace::MODEL_PARAM => "1"), headers: partial
    assert_includes inertia_props[Operator::Trace::BODY_PROP], read

    get operator_root_path, headers: inertia_headers
    assert_equal shown, inertia_props["attentionItems"].find { |item| item["key"] == "#{Operator::Attention::KIND_HALON_FAILED}-#{run.id}" }["subject"]

    assert_equal shown, Operator::Finder.new(run.id, readable: Operator::Readable.new(->(_workspace, texts) { texts.index_with { shown } })).matches.sole.label
  end

  test "find opens the one record that matches, and lists several" do
    as_operator

    get operator_find_path(q: @run.id)
    assert_redirected_to operator_halon_run_path(@run)

    get operator_find_path(q: "zzzzzz"), headers: inertia_headers
    assert_equal [], inertia_props["matches"]
  end

  private

  def as_operator
    sign_in(@operator, @workspace)
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end
end
