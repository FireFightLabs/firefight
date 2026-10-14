require "test_helper"
require "open3"
require "webrick"

# The OpenCode sandbox/Dockerfile pins, run as a code fix runs it, against a model scripted here in Anthropic's format.
# It needs that OpenCode, named by OPENCODE_BIN. It is skipped on a machine without it, and fails in CI, whose image
# installs it, so a broken install is never passed over in silence.
class OpencodePermissionsTest < ActiveSupport::TestCase
  BIN = ENV["OPENCODE_BIN"].to_s
  PINNED = Rails.root.join("sandbox/Dockerfile").read[/opencode-ai@([\d.]+)/, 1]
  MODEL = "claude-sonnet-4-5".freeze
  STRAY = "cd /runs/*; ls".freeze
  SAID = "I wrote fixed.txt after that command was refused.".freeze

  setup do
    unless File.executable?(BIN)
      missing = "OpenCode is not installed. Set OPENCODE_BIN to the opencode sandbox/Dockerfile pins."
      ENV["CI"].present? ? flunk(missing) : skip(missing)
    end
    installed, = Open3.capture2(BIN, "--version")
    assert_equal PINNED, installed.strip, "The OpenCode at #{BIN} is not the one sandbox/Dockerfile pins."

    @root = Dir.mktmpdir
    @copy = File.join(@root, "copy")
    FileUtils.mkdir_p([ @copy, File.join(@root, "home"), File.join(@root, "tmp") ])
    git("init", "-q")
    File.write(File.join(@copy, "README.md"), "hi\n")
    git("add", "README.md")
    git("-c", "user.name=a", "-c", "user.email=a@example.com", "commit", "-qm", "init")
    @server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
    steps = [ [ "bash", { "command" => STRAY, "description" => "Look around" } ],
              [ "write", { "filePath" => File.join(@copy, "fixed.txt"), "content" => "fixed\n" } ], [ nil, SAID ] ]
    @server.mount_proc("/") { |request, response| answer(request, response, steps) }
    @thread = Thread.new { @server.start }
  end

  teardown do
    @server&.shutdown
    @thread&.join
    FileUtils.rm_rf(@root) if @root
  end

  test "a call outside the copy fails alone with an error the model reads, and the agent carries on and finishes" do
    output = run_agent("permission" => Integrations::Packs::Github::Fixing::PERMISSIONS, "agent" => Integrations::Packs::Github::Fixing::AGENTS)

    assert_not_includes output, "auto-rejecting", "nothing is left for opencode run to ask"
    stray = tool_uses(output).find { |part| part.dig("state", "input", "command") == STRAY }
    assert_equal "error", stray.dig("state", "status")
    assert_match "prevents you from using this specific tool call", stray.dig("state", "error")
    assert_equal "fixed\n", File.read(File.join(@copy, "fixed.txt")), "the agent went on to its next step"
    events = Integrations::SandboxAgentEvents.new(Chat::CodeFixProgress.start)
    events.read(output)
    assert_equal SAID, events.last_said
    assert_nil events.stop_reason(output)
  end

  test "the same call left for opencode run to ask about is rejected and ends the run, which is why nothing is left to ask" do
    output = run_agent("permission" => { "edit" => "allow", "bash" => "allow" })

    assert_includes output, "auto-rejecting"
    assert_not File.exist?(File.join(@copy, "fixed.txt")), "the run ended at the rejected call"
    assert_match "It asked for permission to reach", Integrations::SandboxAgentEvents.new(Chat::CodeFixProgress.start).stop_reason(output)
  end

  private

  def run_agent(settings)
    config = File.join(@root, "opencode.json")
    File.write(config, { "autoupdate" => false, "share" => "disabled",
                         "provider" => { "anthropic" => { "options" => { "baseURL" => "http://127.0.0.1:#{@server.config[:Port]}/v1", "apiKey" => "scripted" },
                                                          "models" => { MODEL => {} } } } }.merge(settings).to_json)
    home = File.join(@root, "home")
    env = { "HOME" => home, "XDG_CONFIG_HOME" => "#{home}/.config", "XDG_DATA_HOME" => "#{home}/.local/share", "XDG_CACHE_HOME" => "#{home}/.cache",
            "XDG_STATE_HOME" => "#{home}/.local/state", "TMPDIR" => File.join(@root, "tmp"), "OPENCODE_CONFIG" => config,
            # OpenCode takes the directory it works in from PWD, which a shell sets as the sandbox's does.
            "PWD" => @copy }
    output, = Open3.capture2e(env, BIN, "run", "--model", "anthropic/#{MODEL}", "--format", "json", "Fix it", chdir: @copy, stdin_data: "")
    output
  end

  def tool_uses(output)
    output.lines.filter_map { |line| JSON.parse(line) rescue nil }.select { |event| event["type"] == "tool_use" }.map { |event| event["part"] }
  end

  # Each turn that offers tools gets the next scripted step, and a call without tools, such as for a title, gets a title.
  def answer(request, response, steps)
    body = JSON.parse(request.body.to_s)
    tool, said = body["tools"].present? ? (steps.shift || [ nil, "Done." ]) : [ nil, "Title" ]
    block = tool ? { type: "tool_use", id: "toolu_#{SecureRandom.hex(4)}", name: tool, input: {} } : { type: "text", text: "" }
    delta = tool ? { type: "input_json_delta", partial_json: said.to_json } : { type: "text_delta", text: said }
    events = [
      { type: "message_start", message: { id: "msg_#{SecureRandom.hex(4)}", type: "message", role: "assistant", model: MODEL, content: [],
                                          stop_reason: nil, usage: { input_tokens: 10, output_tokens: 1 } } },
      { type: "content_block_start", index: 0, content_block: block }, { type: "content_block_delta", index: 0, delta: delta },
      { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: tool ? "tool_use" : "end_turn" }, usage: { output_tokens: 5 } },
      { type: "message_stop" }
    ]
    response["Content-Type"] = "text/event-stream"
    response.body = events.map { |event| "event: #{event[:type]}\ndata: #{event.to_json}\n\n" }.join
  end

  def git(*args)
    _output, status = Open3.capture2e("git", *args, chdir: @copy)
    assert status.success?, "git #{args.join(' ')} failed"
  end
end
