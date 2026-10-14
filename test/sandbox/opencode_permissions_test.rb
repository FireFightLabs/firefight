require "test_helper"
require "open3"
require "webrick"

# A code fix's agent run for real: Fixing::RUN with its driver and the OpenCode sandbox/Dockerfile pins, against a model
# scripted here in Anthropic's format and Firefight's permissions endpoint stood in for here. It needs that OpenCode,
# named by OPENCODE_BIN. It is skipped on a machine without it, and fails in CI, whose image installs it, so a broken
# install is never passed over in silence.
class OpencodePermissionsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Fixing = Integrations::Packs::Github::Fixing
  BIN = ENV["OPENCODE_BIN"].to_s
  PINNED = Rails.root.join("sandbox/Dockerfile").read[/opencode-ai@([\d.]+)/, 1]
  MODEL = "claude-sonnet-4-5".freeze
  STRAY = "cd /runs/*; ls".freeze
  LOOPED = "ls".freeze
  SAID = "I wrote fixed.txt.".freeze
  HOUSE_RULE = "Always name branches after the ticket.".freeze

  setup do
    unless File.executable?(BIN)
      missing = "OpenCode is not installed. Set OPENCODE_BIN to the opencode sandbox/Dockerfile pins."
      ENV["CI"].present? ? flunk(missing) : skip(missing)
    end
    installed, = Open3.capture2(BIN, "--version")
    assert_equal PINNED, installed.strip, "The OpenCode at #{BIN} is not the one sandbox/Dockerfile pins."

    @root = Dir.mktmpdir
    @copy = File.join(@root, "copy")
    @bin = File.join(@root, "bin")
    FileUtils.mkdir_p([ @copy, @bin, File.join(@root, "home") ])
    File.symlink(BIN, File.join(@bin, "opencode"))
    File.write(File.join(@copy, "README.md"), "hi\n")
    File.write(File.join(@copy, "AGENTS.md"), "#{HOUSE_RULE}\n")
    # A repository that would let its agent ask about everything, which the box never reads.
    File.write(File.join(@copy, "opencode.json"), { "permission" => { "*" => "ask" } }.to_json)
    git("init", "-q")
    git("add", ".")
    git("-c", "user.name=a", "-c", "user.email=a@example.com", "commit", "-qm", "init")
    @systems = []
    @asked = []
    request = CodeAgent::Request.new(principal: workspace_memberships(:bob_workspace_one), source: AbilityGateway::SOURCE_MCP, place: nil, tool_call_id: "call_1")
    @session, @token = CodeAgentSession.open!(workspace: workspaces(:slack_workspace_one), choice: FirefightAi::ModelChoice.new(model: MODEL, provider: "anthropic"),
                                              repository: "acme/api", request: request)
    @server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    @thread = Thread.new { @server.start }
  end

  teardown do
    @server&.shutdown
    @thread&.join
    FileUtils.rm_rf(@root) if @root
  end

  test "a call outside the copy fails alone with an error the model reads, the repository's own settings are ignored, and its instructions are read" do
    output = run_agent([ [ [ "bash", { "command" => STRAY, "description" => "Look around" } ] ], [ write_step ] ])

    stray = tool_uses(output).find { |part| part.dig("state", "input", "command") == STRAY }
    assert_equal "error", stray.dig("state", "status"), output
    assert_match "prevents you from using this specific tool call", stray.dig("state", "error")
    assert_equal [ "fixed.txt" ], changed(output), "the agent went on to its next step"
    assert_empty @asked, "nothing was asked, though the repository's own settings would have asked about everything"
    assert(@systems.any? { |system| system.include?(HOUSE_RULE) }, "the repository's AGENTS.md reached the model")
    assert_equal SAID, events(output).last_said
  end

  test "the same call a third time is put to Halon with what OpenCode asks, Halon lets it through, and the agent carries on" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide).with do |asked:, can_ask:, **|
      asked == "The coding agent repeated bash 3 times in a row with the same input: #{LOOPED}" && !can_ask
    end.returns(FirefightAi::PermissionJudge::Decision.new(decision: FirefightAi::PermissionJudge::ALLOW, reason: "Listing is cheap and it is about to write.", lean: nil))

    output = run_agent([ looping, [ write_step ] ])

    assert_equal 3, tool_uses(output).count { |part| part.dig("state", "input", "command") == LOOPED && part.dig("state", "status") == "completed" }
    assert_equal [ "fixed.txt" ], changed(output)
    assert_match(/^AGENT_EXIT 0$/, output)
    assert_equal "OpenCode repeated bash 3 times in a row with the same input: #{LOOPED}, and Halon let it continue because listing is cheap and it is about to write",
                 @session.permissions.sole.step_words
  end

  test "a third call Halon refuses ends the run with Halon's reason, which the change's answer gives" do
    FirefightAi::PermissionJudge.any_instance.expects(:decide)
                                .returns(FirefightAi::PermissionJudge::Decision.new(decision: FirefightAi::PermissionJudge::STOP, reason: "It listed the same folder three times.", lean: nil))

    output = run_agent([ looping, [ write_step ] ])

    assert_empty changed(output)
    assert_match(/^AGENT_EXIT 1$/, output)
    assert_equal "Halon refused this step. It listed the same folder three times", events(output).stop_reason(output)
  end

  private

  def write_step = [ "write", { "filePath" => File.join(@copy, "fixed.txt"), "content" => "fixed\n" } ]

  # OpenCode asks about a repeat when one answer calls the same tool with the same input three times
  # (session/processor.ts at 1.18.34).
  def looping = Array.new(3) { [ "bash", { "command" => LOOPED, "description" => "List" } ] }

  # steps are the model's answers in turn, each a list of blocks, a tool call or words.
  def run_agent(steps)
    script = [ *steps, [ [ nil, SAID ] ] ]
    @server.mount_proc("/v1") { |request, response| answer(request, response, script) }
    # Firefight's own endpoint, reached through the app as the box reaches it, with Halon's decision made at once.
    @server.mount_proc("/permissions") do |request, response|
      @asked << request.body
      answered = perform_enqueued_jobs do
        Rack::MockRequest.new(Rails.application).post(Fixing::PERMISSIONS_PATH, input: request.body, "CONTENT_TYPE" => "application/json",
                                                                                "HTTP_AUTHORIZATION" => request["Authorization"])
      end
      response.status = answered.status
      response["Content-Type"] = "application/json"
      response.body = answered.body
    end
    base = "http://127.0.0.1:#{@server.config[:Port]}"
    config = { "autoupdate" => false, "share" => "disabled",
               "provider" => { "anthropic" => { "options" => { "baseURL" => "#{base}/v1", "apiKey" => @token }, "models" => { MODEL => {} } } },
               "permission" => Fixing::PERMISSIONS, "agent" => Fixing::AGENTS, "instructions" => [ Fixing::INSTRUCTIONS ],
               "mcp" => { Fixing::TOOLS_SERVER => { "type" => "remote", "url" => "#{base}/mcp", "enabled" => true, "headers" => { "Authorization" => "Bearer #{@token}" } } } }
    home = File.join(@root, "home")
    env = { "PATH" => "#{@bin}:#{ENV.fetch('PATH')}", "HOME" => home, "XDG_CONFIG_HOME" => "#{home}/.config", "XDG_DATA_HOME" => "#{home}/.local/share",
            "XDG_CACHE_HOME" => "#{home}/.cache", "XDG_STATE_HOME" => "#{home}/.local/state", "SANDBOX_PROGRESS" => File.join(@root, "progress") }
    output, = Open3.capture2(env, "bash", "-c", Fixing::RUN, Fixing::AGENT, "Fix it", "anthropic/#{MODEL}", "", "", "main", "halon/fix-1", "Fix", "",
                             "#{base}/permissions", chdir: @copy, stdin_data: "credential\n#{config.to_json}\n#{Fixing::DRIVER}")
    # What the box hands back keeps only the log's tail, so the whole run is read from its progress.
    "#{output}#{File.read(File.join(@root, 'progress'))}"
  end

  # The files the run's change touched, since the script puts the copy back once it kept the change.
  def changed(output) = Integrations::Packs::Github.new(Integration.new(provider: "github")).send(:read_change, output).counts.keys

  def events(output)
    events = Integrations::SandboxAgentEvents.new(Chat::CodeFixProgress.start)
    events.read(output)
    events
  end

  def tool_uses(output)
    output.lines.filter_map { |line| JSON.parse(line) rescue nil }.select { |event| event["type"] == "tool_use" }.map { |event| event["part"] }
  end

  # Each turn that offers tools gets the next scripted answer, and a call without tools, such as for a title, gets a title.
  def answer(request, response, script)
    body = JSON.parse(request.body.to_s)
    @systems << Array(body["system"]).map { |part| part.is_a?(Hash) ? part["text"].to_s : part.to_s }.join("\n")
    blocks = body["tools"].present? ? (script.shift || [ [ nil, "Done." ] ]) : [ [ nil, "Title" ] ]
    events = [ { type: "message_start", message: { id: "msg_#{SecureRandom.hex(4)}", type: "message", role: "assistant", model: MODEL, content: [],
                                                   stop_reason: nil, usage: { input_tokens: 10, output_tokens: 1 } } } ]
    blocks.each_with_index do |(tool, said), index|
      block = tool ? { type: "tool_use", id: "toolu_#{SecureRandom.hex(4)}", name: tool, input: {} } : { type: "text", text: "" }
      delta = tool ? { type: "input_json_delta", partial_json: said.to_json } : { type: "text_delta", text: said }
      events.push({ type: "content_block_start", index: index, content_block: block }, { type: "content_block_delta", index: index, delta: delta },
                  { type: "content_block_stop", index: index })
    end
    events.push({ type: "message_delta", delta: { stop_reason: blocks.any?(&:first) ? "tool_use" : "end_turn" }, usage: { output_tokens: 5 } },
                { type: "message_stop" })
    response["Content-Type"] = "text/event-stream"
    response.body = events.map { |event| "event: #{event[:type]}\ndata: #{event.to_json}\n\n" }.join
  end

  def git(*args)
    _output, status = Open3.capture2e("git", *args, chdir: @copy)
    assert status.success?, "git #{args.join(' ')} failed"
  end
end
