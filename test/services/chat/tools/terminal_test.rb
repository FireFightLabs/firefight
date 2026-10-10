require "test_helper"

class Chat::Tools::TerminalTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
    @chat = @conversation.chat_record
    Integrations::Terminal.stubs(:available?).returns(true)
    Integrations::Terminal.stubs(:region).returns("europe-west")
    Chat::Terminal.stubs(:relay_base).returns("https://ff.example/sandbox_relay")
  end

  test "neither the terminal nor the outside check is offered where this install has no sandbox" do
    Integrations::Terminal.stubs(:available?).returns(false)

    assert_empty Chat::Tools::Terminal.all(@turn)
    assert_empty Chat::Tools::OutsideCheck.all(@turn)
    assert_not_includes Conversation::Tools.for(@turn, offer: ->(_) { }).map(&:name), Chat::Tools::Terminal::NAME
  end

  test "a command runs in the run's box with a token of its own, and the token ends with the command" do
    handed = nil
    Integrations::Terminal.any_instance.expects(:run).with do |command, env:, timeout:|
      handed = env
      command == "echo hi" && timeout == Chat::Tools::Terminal::DEFAULT_TIMEOUT
    end.returns("stdout" => "hi\n", "stderr" => "", "exit_code" => 0, "timed_out" => false)

    said = tool.call(command: "echo hi")

    assert_includes said, "Exit code 0."
    assert_includes said, "stdout:\nhi"
    assert_equal "https://ff.example/sandbox_relay", handed[Chat::Terminal::URL_VARIABLE]
    assert_nil Chat::TerminalSession.authenticate(handed[Chat::Terminal::TOKEN_VARIABLE]), "the token ends with the command"
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::SANDBOX_COMMAND)
    assert_equal [ Ability::Invocation::DECISION_ALLOW, @member ], [ invocation.decision, invocation.principal ]
  end

  test "a command that prints its own token never hands it to the chat" do
    session, = Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
    Chat::TerminalSession.stubs(:open!).returns([ session, "the-token" ])
    Integrations::Terminal.any_instance.expects(:run).with { |_command, env:, **| env[Chat::Terminal::TOKEN_VARIABLE] == "the-token" }
                          .returns("stdout" => "FIREFIGHT_RELAY_TOKEN=the-token\n", "stderr" => "", "exit_code" => 0)

    said = tool.call(command: "env")

    assert_not_includes said, "the-token"
    assert_includes said, "FIREFIGHT_RELAY_TOKEN=#{Chat::Tools::Terminal::TOKEN_SHOWN}"
  end

  test "a saved result is placed as a file before the command, so a script reads it whole" do
    saved = @chat.saved_results.keep!(tool_name: "search_logs", text: "a 500\nb 200\nc 500")
    Integrations::Terminal.any_instance.expects(:place).with("#{saved.handle}.txt", "a 500\nb 200\nc 500").returns("/terminal/results/#{saved.handle}.txt")
    Integrations::Terminal.any_instance.expects(:run).returns("stdout" => "2\n", "stderr" => "", "exit_code" => 0)

    said = tool.call(command: "grep -c 500 results/#{saved.handle}.txt", results: [ saved.handle ])

    assert_includes said, "Placed /terminal/results/#{saved.handle}.txt."
    assert_includes said, "stdout:\n2"
  end

  test "a result that is not saved is said before anything runs" do
    Integrations::Terminal.any_instance.expects(:run).never

    assert_match "Nothing is saved as result_9", tool.call(command: "cat results/result_9.txt", results: [ "result_9" ])
  end

  test "a command that only reads is never put to the person, and one that changes something is" do
    terminal = tool
    reads = stub(id: "call_r", arguments: { "command" => "ls" })
    changes = stub(id: "call_c", arguments: { "command" => "ff northflank_api_request method=POST path=services/web/restart", "changes" => true })

    assert terminal.requires_approval?
    assert_equal true, terminal.approval_resolver.call(reads)
    assert_nil terminal.approval_resolver.call(changes)
  end

  test "an investigation only reads, so a command saying it changes something is refused and changes is not offered" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    run = Chat::Tools::Terminal.new(investigation)
    Integrations::Terminal.any_instance.expects(:run).never

    assert_not run.requires_approval?
    assert_not_includes run.parameters_schema["properties"].keys, Chat::Tools::Terminal::CHANGES_ARG
    assert_match "only reads", run.call(command: "ff x", changes: true)
  end

  test "a box that cannot start is said and the call is marked failed" do
    Integrations::Terminal.any_instance.stubs(:run).raises(Integrations::Unavailable, "Code reading cannot run right now: no provider.")
    Chat::Tools.expects(:mark_failed).with(@turn, "call_1")

    assert_includes tool.call(command: "ls", tool_call: stub(id: "call_1")), "The command did not run: Code reading cannot run right now"
  end

  test "a command past its time limit says so" do
    Integrations::Terminal.any_instance.expects(:run).with { |_command, timeout:, **| timeout == Chat::Tools::Terminal::MAX_TIMEOUT }
                          .returns("stdout" => "", "stderr" => "", "exit_code" => nil, "timed_out" => true)

    assert_includes tool.call(command: "sleep 99999", timeout_seconds: 99_999), "Stopped after the time limit"
  end

  private

  def tool = Chat::Tools::Terminal.new(@turn)
end
