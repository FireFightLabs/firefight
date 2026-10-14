require "test_helper"

# How a code fix's driver starts `opencode serve` and gives up on it, on the box's Node, through Fixing::RUN. OpenCode
# 1.18.34 listens before it attaches its handler, and a connection accepted in between is never answered, which once
# held every code fix in the box until its time ran out. A stand in that does the same decides when it listens, says
# so, answers or never answers, so each case is certain rather than left to how fast a machine starts OpenCode.
class OpencodeDriverTest < ActiveSupport::TestCase
  include SandboxNodeHelper

  Fixing = Integrations::Packs::Github::Fixing
  SAID = "Fixed it.".freeze

  # Listens at once, and in every mode but answers only once it says it is listening, as OpenCode does. A connection it
  # took before then is written down and left unanswered.
  STAND_IN = <<~JS.freeze
    const http = require("node:http")
    const fs = require("node:fs")
    const mode = process.env.STAND_IN_MODE
    if (mode === "exits") {
      process.exit(3)
    }
    const port = Number(process.argv[process.argv.indexOf("--port") + 1])
    const auth = "Basic " + Buffer.from("opencode:" + process.env.OPENCODE_SERVER_PASSWORD).toString("base64")
    const streams = []
    const server = http.createServer()
    let answering = false
    server.on("connection", () => {
      if (!answering) {
        fs.appendFileSync(process.env.STAND_IN_EARLY, "early\\n")
      }
    })
    const send = (event) => streams.forEach((stream) => stream.write("data: " + JSON.stringify(event) + "\\n\\n"))
    const answer = (request, response) => {
      if (request.headers.authorization !== auth) {
        response.writeHead(401).end()
      } else if (request.url === "/event") {
        response.writeHead(200, { "Content-Type": "text/event-stream" }).flushHeaders()
        streams.push(response)
      } else if (request.method === "POST" && request.url === "/session") {
        response.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify({ id: "ses_standin" }))
      } else if (request.method === "POST" && request.url === "/session/ses_standin/prompt_async") {
        response.writeHead(204).end()
        send({ type: "message.part.updated", properties: { part: { sessionID: "ses_standin", type: "text", text: #{SAID.to_json}, time: { end: 1 } } } })
        send({ type: "session.status", properties: { sessionID: "ses_standin", status: { type: "idle" } } })
      } else {
        response.writeHead(404).end()
      }
    }
    server.listen(port, "127.0.0.1", () => {
      if (mode === "silent") {
        return
      }
      setTimeout(() => {
        if (mode !== "stalls") {
          answering = true
          server.on("request", answer)
        }
        console.log("opencode server listening on http://127.0.0.1:" + port)
      }, mode === "stalls" ? 0 : 1500)
    })
  JS

  setup do
    require_agent_node!
    @root = Dir.mktmpdir
    @copy = File.join(@root, "copy")
    @bin = File.join(@root, "bin")
    FileUtils.mkdir_p([ @copy, @bin ])
    File.write(File.join(@bin, "opencode"), "#!#{AGENT_NODE}\n#{STAND_IN}")
    File.chmod(0o755, File.join(@bin, "opencode"))
    File.write(File.join(@copy, "README.md"), "hi\n")
    system("git", "init", "-q", chdir: @copy, exception: true)
    system("git", "add", ".", chdir: @copy, exception: true)
    system("git", "-c", "user.name=a", "-c", "user.email=a@example.com", "commit", "-qm", "init", chdir: @copy, exception: true)
  end

  teardown do
    FileUtils.rm_rf(@root) if @root
  end

  test "nothing reaches OpenCode before it says it is listening, so the run never waits on a connection it will not answer" do
    output, took = run_agent("late")

    assert_match(/^AGENT_EXIT 0$/, output)
    refute File.exist?(File.join(@root, "early")), "the driver connected before OpenCode said it was listening"
    assert_equal SAID, events(output).last_said
    assert_operator took, :<, 15, output
  end

  test "an OpenCode that never says it is listening ends the run within its start time, saying so plainly" do
    output, took = run_agent("silent")

    assert_match(/^AGENT_EXIT 1$/, output)
    assert_equal "OpenCode did not start within 30 seconds", events(output).stop_reason(output)
    assert_operator took, :<, 45, output
  end

  test "an OpenCode that listens and never answers ends the run within its answer time, saying so plainly" do
    output, took = run_agent("stalls")

    assert_match(/^AGENT_EXIT 1$/, output)
    assert_equal "OpenCode did not answer within 30 seconds", events(output).stop_reason(output)
    assert_operator took, :<, 45, output
  end

  test "an OpenCode that stops ends the run at once, saying how" do
    output, took = run_agent("exits")

    assert_match(/^AGENT_EXIT 1$/, output)
    assert_equal "OpenCode stopped unexpectedly with exit code 3", events(output).stop_reason(output)
    assert_operator took, :<, 15, output
  end

  private

  def run_agent(mode)
    config = { "mcp" => { Fixing::TOOLS_SERVER => { "type" => "remote", "url" => "http://127.0.0.1:9/mcp", "headers" => { "Authorization" => "Bearer token" } } } }
    env = { "PATH" => "#{@bin}:#{ENV.fetch('PATH')}", "HOME" => @root, "AGENT_NODE" => AGENT_NODE, "STAND_IN_MODE" => mode,
            "STAND_IN_EARLY" => File.join(@root, "early") }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    output, = Open3.capture2(env, "bash", "-c", Fixing::RUN, Fixing::AGENT, "Fix it", "anthropic/model", "", "", "main", "halon/fix-1", "Fix", "",
                             "http://127.0.0.1:9/permissions", chdir: @copy, stdin_data: "credential\n#{config.to_json}\n#{Fixing::DRIVER}")
    [ output, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started ]
  end

  def events(output)
    events = Integrations::SandboxAgentEvents.new(Chat::CodeFixProgress.start)
    events.read(output)
    events
  end
end
