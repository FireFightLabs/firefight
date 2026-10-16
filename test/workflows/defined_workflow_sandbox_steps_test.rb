require "test_helper"

class DefinedWorkflowSandboxStepsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # An answer as Net::HTTP hands one to the block a request is read in.
  FakeResponse = Struct.new(:code, :text, :headers) do
    def read_body = yield(text)
    def [](name) = headers.to_h[name]
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
    Integrations::Terminal.stubs(:available?).returns(true)
    Integrations::CodeReading.stubs(:close)
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def check(after) = step("check", "check_from_outside", { "url" => "https://shop.example.com" }).merge("id" => "check_#{after}", "name" => "check_#{after}")

  def published(name, steps:, edges: [], trigger: { "kind" => "manual", "inputs" => [] })
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: trigger, steps: steps, edges: edges)
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    workflow.reload
  end

  def start(workflow, **options)
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options) }
    run.reload
  end

  def output(run, key) = run.steps.find_by!(step_key: key).output

  def outside_answer = { "http" => { "status" => 200, "final_url" => "https://shop.example.com/", "certificate_trusted" => true, "timings_ms" => { "total" => 120 } },
                         "tls" => { "days_left" => 41 }, "dns" => { "records" => [ { "type" => "A", "value" => "93.184.216.34" } ] } }

  test "run command runs in the run's own box with the step's data placed as a file, and hands on what it printed as JSON" do
    Integrations::Terminal.any_instance.expects(:place).with(DefinedWorkflow::Steps::Sandbox::DATA_FILE, "{\n  \"service\": \"web\"\n}").returns("/terminal/results/step_data.json")
    Integrations::Terminal.any_instance.expects(:run).with { |command, env:, timeout:| command == "jq .service $STEP_DATA" && env["STEP_DATA"] == "/terminal/results/step_data.json" && timeout == 30 }
                          .returns({ "exit_code" => 0, "stdout" => "{\"count\": 3}\n", "stderr" => "" })
    workflow = published("Count", steps: [ step("count", "run_command", { "command" => "jq .service $STEP_DATA", "data" => { "service" => "web" }, "timeout_seconds" => 30 }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "count" => 3 }, output(run, "count")["data"])
    assert_equal AbilityGateway::SOURCE_WORKFLOW, run.invocations.sole.source
  end

  # The run's box started and ten seconds passing while its command runs.
  def ten_seconds_in_the_box(workflow)
    proc do |*|
      CodeBox.create!(workspace: @workspace, key: workflow.runs.sole.code_box_key, provider: Integrations::Sandboxes::Boat::KEY, box_ref: "bx_9", address: "https://box.example.com",
                      secret: "k", last_used_at: Time.current, box_started_at: Time.current, hourly_micros: 360_000)
      travel 10.seconds
      true
    end
  end

  test "a sandbox step keeps how long it used the run's box and what that cost, and the run's sandbox spend is the box's time" do
    workflow = published("Count", steps: [ step("count", "run_command", { "command" => "ls" }) ])
    Integrations::Terminal.any_instance.stubs(:run).with(&ten_seconds_in_the_box(workflow)).returns({ "exit_code" => 0, "stdout" => "", "stderr" => "" })

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    counted = run.steps.sole
    assert_in_delta 10, counted.sandbox_seconds, 1
    assert_in_delta 1_000, counted.sandbox_micros, 100
    assert_in_delta 1_000, run.sandbox_spent_micros, 100
  end

  test "check from outside and the browser keep their sandbox time too" do
    workflow = published("Look", steps: [ check("x") ])
    Integrations::Terminal.any_instance.stubs(:check).with(&ten_seconds_in_the_box(workflow)).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))

    assert_in_delta 10, start(workflow).steps.sole.sandbox_seconds, 1

    page = published("Page", steps: [ step("page", "browser", { "url" => "https://shop.example.com" }) ])
    answer = Chat::BrowserCheck::Answer.new({ "viewports" => [ { "name" => "desktop", "status" => 200, "title" => "Shop" } ] }, check: Chat::BrowserCheck.from({ "url" => "https://shop.example.com" }))
    Chat::Browsing.stubs(:run).with(&ten_seconds_in_the_box(page)).returns(answer)

    assert_in_delta 10, start(page).steps.sole.sandbox_seconds, 1
  end

  test "once the run reached its spending ceiling a sandbox step does not start" do
    workflow = published("Count", steps: [ step("count", "run_command", { "command" => "ls" }) ])
    workflow.update!(cost_cap_cents: 25)
    Workflow::Run.any_instance.stubs(:spent_cents).returns(25)
    Integrations::Terminal.any_instance.expects(:run).never

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_equal "count failed. This run reached its spending ceiling of $0.25, so this step did not run.", run.error
  end

  test "a command that fails fails the step, and one that says it changes something is only shown in a test run" do
    Integrations::Terminal.any_instance.stubs(:run).returns({ "exit_code" => 2, "stdout" => "", "stderr" => "no such file\n" })
    failing = published("Fails", steps: [ step("bad", "run_command", { "command" => "cat nothing" }) ])
    run = start(failing)
    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "exit code 2. no such file", run.error

    Integrations::Terminal.any_instance.expects(:run).never
    changing = published("Restart", steps: [ step("restart", "run_command", { "command" => "ff restart resource=web", "changes" => true, "undo" => "Nothing to undo." }), check("restart") ],
                                    edges: [ { "from" => "restart", "to" => "check_restart" } ])
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    tried = start(changing, test: true)
    assert_equal true, output(tried, "restart")["simulated"]
  end

  test "ff in a step's command calls as the workflow's own run, and only reads unless the step says it changes something" do
    workflow = published("Look", steps: [ check("x") ])
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    record = start(workflow).steps.sole
    agent_run = Workflow::AgentRun.new(run: record.run, record: record)
    session, = Chat::TerminalSession.open!(agent_run, changes: false, lasts: 1.minute)

    relayed = Chat::Terminal::Relay.agent_run_of(session)

    assert_kind_of Workflow::AgentRun, relayed
    assert_equal workflow.agent, relayed.acting_principal
    assert_not session.changes_allowed
  end

  test "run script keeps the script and its data in the box and reads what it printed as JSON" do
    Integrations::Terminal.any_instance.stubs(:place).with("script.py", anything).returns("/terminal/results/script.py")
    Integrations::Terminal.any_instance.stubs(:place).with(DefinedWorkflow::Steps::Sandbox::DATA_FILE, "[1,2]").returns("/terminal/results/step_data.json")
    Integrations::Terminal.any_instance.expects(:run).with { |command, **| command == "python3 /terminal/results/script.py < /terminal/results/step_data.json" }
                          .returns({ "exit_code" => 0, "stdout" => "{\"total\": 3}", "stderr" => "" })
    workflow = published("Sum", steps: [ step("sum", "run_script", { "language" => "python", "script" => "print(1)", "data" => "[1,2]" }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "total" => 3 }, output(run, "sum")["result"])
  end

  test "check from outside says how an address answers, its certificate and its DNS" do
    Integrations::Terminal.any_instance.expects(:check).with("https://shop.example.com", method: "GET").returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    workflow = published("Outside", steps: [ check("x") ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal [ true, 200, 41, "fra" ], output(run, "check_x").values_at("ok", "status", "certificate_days_left", "region")
  end

  test "the browser reads a page and keeps its screenshots on the run, and never sends from a run nobody pressed" do
    jpeg = Base64.strict_encode64("\xFF\xD8\xFF\xE0fake".b)
    viewport = { "name" => "desktop", "status" => 200, "title" => "Shop", "final_url" => "https://shop.example.com/", "page_text" => "Welcome", "screenshot" => jpeg }
    Chat::Browsing.stubs(:run).returns(Chat::BrowserCheck::Answer.new({ "viewports" => [ viewport ] }, check: Chat::BrowserCheck.from({ "url" => "https://shop.example.com" })))
    workflow = published("Look", steps: [ step("look", "browser", { "url" => "https://shop.example.com", "viewports" => [ "desktop" ] }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal [ true, "Shop", 1 ], output(run, "look").values_at("ok", "title", "screenshots")
    assert_equal 1, run.steps.find_by!(step_key: "look").chat.screenshots.count

    sending = { "url" => "https://shop.example.com", "steps" => [ { "action" => "click", "text" => "Buy" } ], "send_step" => 1, "undo" => "Cancel the order." }
    seller = published("Buy", trigger: { "kind" => "schedule", "inputs" => [], "repeat" => "days", "at" => "09:00", "days" => [ 1 ], "time_zone" => "UTC" },
                              steps: [ step("buy", "browser", sending), check("buy") ], edges: [ { "from" => "buy", "to" => "check_buy" } ])
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    scheduled = start(seller, trigger_kind: Workflow::Trigger::KIND_SCHEDULE)
    assert_equal Workflow::Run::STATUS_FAILED, scheduled.status
    assert_match "Nobody pressed Run", scheduled.error
  end

  test "an HTTP request reads through the guard, and a connection's credentials go only to its own hosts" do
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns("93.184.216.34")
    sent = []
    answer = FakeResponse.new("200", "{\"deploys\": 2}", { "Content-Type" => "application/json" })
    Net::HTTP.any_instance.stubs(:request).with { |request| sent << request }.yields(answer).returns(answer)
    workflow = published("Read", steps: [ step("read", "http_request", { "method" => "GET", "url" => "https://api.example.com/deploys", "headers" => [ "Accept: application/json" ] }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal({ "deploys" => 2 }, output(run, "read")["data"])
    assert_equal "application/json", sent.sole["Accept"]

    linear = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear", slug: "linear")
    linear.integration_environments.create!
    Integrations::Credentials.stubs(:headers_for).returns({ "Authorization" => "Bearer lin_secret_token" })
    elsewhere = published("Leak", steps: [ step("leak", "http_request", { "url" => "https://evil.example.com/", "connection" => "linear" }) ])
    refused = start(elsewhere)
    assert_equal Workflow::Run::STATUS_FAILED, refused.status
    assert_match "go only to its own hosts", refused.error
    assert_equal 1, sent.size

    plain = published("Plain", steps: [ step("plain", "http_request", { "url" => "http://api.linear.app/graphql", "connection" => "linear" }) ])
    refused = start(plain)
    assert_equal Workflow::Run::STATUS_FAILED, refused.status
    assert_match "A connection's credentials go only over https, and http://api.linear.app/graphql is not.", refused.error
    assert_equal 1, sent.size
  end

  test "a browser step that sends keeps only the screenshots of the send, as many as it says it kept" do
    jpeg = Base64.strict_encode64("\xFF\xD8\xFF\xE0fake".b)
    page = { "name" => "desktop", "status" => 200, "title" => "Shop", "final_url" => "https://shop.example.com/", "page_text" => "Welcome", "screenshot" => jpeg }
    looked = page.merge("stopped" => { "step" => 1, "would_send" => { "method" => "POST", "url" => "https://shop.example.com/orders" } })
    checked = Chat::BrowserCheck.from({ "url" => "https://shop.example.com" })
    Integrations::Terminal.stubs(:available?).returns(true)
    Chat::Browsing.stubs(:run).returns(Chat::BrowserCheck::Answer.new({ "viewports" => [ looked ] }, check: checked))
                  .then.returns(Chat::BrowserCheck::Answer.new({ "viewports" => [ page ] }, check: checked))
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    sending = { "url" => "https://shop.example.com", "viewports" => [ "desktop" ], "steps" => [ { "action" => "click", "text" => "Buy" } ], "send_step" => 1,
                "undo" => "Cancel the order." }
    workflow = published("Buy", steps: [ step("buy", "browser", sending), check("buy") ], edges: [ { "from" => "buy", "to" => "check_buy" } ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal true, output(run, "buy")["sent"]
    assert_equal 1, output(run, "buy")["screenshots"]
    assert_equal 1, run.steps.find_by!(step_key: "buy").chat.screenshots.count
  end

  test "a browser step sends only the whole request it looked at, and fails in words when the page now sends another" do
    jpeg = Base64.strict_encode64("\xFF\xD8\xFF\xE0fake".b)
    page = { "name" => "desktop", "status" => 200, "title" => "Shop", "final_url" => "https://shop.example.com/", "page_text" => "Welcome", "screenshot" => jpeg }
    shown = { "method" => "POST", "url" => "https://shop.example.com/orders", "fields" => [ { "name" => "amount", "value" => "10" } ], "digest" => "a" * 64 }
    now = { "method" => "POST", "url" => "https://shop.example.com/orders", "fields" => [ { "name" => "amount", "value" => "99" } ], "digest" => "b" * 64 }
    looked = page.merge("stopped" => { "step" => 1, "reason" => "sends_data", "would_send" => shown })
    changed = page.merge("steps" => [ { "n" => 1, "action" => "click", "ok" => true } ], "stopped" => { "step" => 1, "reason" => "changed_request", "would_send" => now })
    checked = Chat::BrowserCheck.from({ "url" => "https://shop.example.com" })
    handed = []
    Integrations::Terminal.stubs(:available?).returns(true)
    Chat::Browsing.stubs(:run).with { |**given| handed << given[:expected_send] }
                  .returns(Chat::BrowserCheck::Answer.new({ "viewports" => [ looked ] }, check: checked))
                  .then.returns(Chat::BrowserCheck::Answer.new({ "viewports" => [ changed ] }, check: checked))
    sending = { "url" => "https://shop.example.com", "viewports" => [ "desktop" ], "steps" => [ { "action" => "click", "text" => "Buy" } ], "send_step" => 1,
                "undo" => "Cancel the order." }
    workflow = published("Buy", steps: [ step("buy", "browser", sending), check("buy") ], edges: [ { "from" => "buy", "to" => "check_buy" } ])

    run = start(workflow)

    assert_equal [ nil, shown.slice("method", "url", "digest") ], handed
    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_equal "buy failed. The page now sends POST https://shop.example.com/orders with amount=99 at step 1, not what it showed just before, so nothing was sent.", run.error
  end

  test "a request that changes something needs its own grant and fails on an error answer" do
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns("93.184.216.34")
    answer = FakeResponse.new("500", "boom", {})
    Net::HTTP.any_instance.stubs(:request).yields(answer).returns(answer)
    workflow = published("Post", steps: [ step("post", "http_request", { "method" => "POST", "url" => "https://api.example.com/x", "body" => "{}", "undo" => "Delete it." }),
                                          check("post") ], edges: [ { "from" => "post", "to" => "check_post" } ])
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: outside_answer, region: "fra"))
    assert_includes workflow.agent.ability_grants.map { |grant| grant.action.key }, Ability::Action::HTTP_SEND

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "answered 500", run.error
  end

  test "send webhook signs the run's data and sends it through an outbound webhook, kept on its deliveries" do
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns("93.184.216.34")
    answer = FakeResponse.new("202", "", {})
    Net::HTTP.any_instance.stubs(:request).yields(answer).returns(answer)
    workflow = published("Tell", steps: [ step("tell", "send_webhook", { "webhook" => "Production Alerts", "event" => "workflow.release", "payload" => { "version" => "1.2" } }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    delivery = WebhookDelivery.find(output(run, "tell")["delivery_id"])
    assert_equal [ "succeeded", "workflow.release", run.id ], [ delivery.state, delivery.event_type, delivery.workflow_run_id ]
    assert_equal({ "version" => "1.2" }, delivery.request_body.dig("data", "payload"))
    assert delivery.request_headers["X-Webhook-Signature"].start_with?("v1=")

    run.destroy!
    assert_nil WebhookDelivery.find_by(id: delivery.id)
  end

  test "an answer that cannot be read fails the request in words, and HEAD is described as a read" do
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(Net::HTTPBadResponse, "wrong status line")
    workflow = published("Garbled", steps: [ step("read", "http_request", { "method" => "GET", "url" => "https://api.example.com/x" }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_FAILED, run.status
    assert_match "api.example.com could not be reached", run.error
    assert_match "GET and HEAD read", Workflow::StepKinds.find("http_request").description
  end
end
