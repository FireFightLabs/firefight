require "test_helper"

# A watch's steps can wait for others. A step with nothing to wait for is read at once, so independent steps go in
# parallel. One whose prerequisites have not all succeeded is not read at all, and once they have it counts only what
# came after them. One whose prerequisite failed is skipped, and the watch ends on the real failure. Only the providers'
# answers are stubbed: the gateway, the capability routing and the watch run as they do in production.
class Conversation::WatchOrderTest < ActiveSupport::TestCase
  include SlackClientStubHelper
  include ActiveJob::TestHelper

  History = Integrations::Capabilities::History
  Step = Chat::Watch::Step

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @github = connect!("github", "GitHub", %w[ci_runs job_log ci_status])
    @render = connect!("render", "Render", %w[deploy_history search_logs describe_resource])
    place!(@github, ResourceMap::KIND_REPOSITORY, "firefight", "acme/firefight")
    place!(@render, ResourceMap::KIND_SERVICE, "web", "srv-web")
    place!(@render, ResourceMap::KIND_SERVICE, "job", "srv-job")
    Investigation.stubs(:unavailable_reason).returns("Halon is off for this test")
    stub_post_message
    @read = []
  end

  # The real case: a health step judged the old container's logs 15 seconds after the release began, since every open
  # step was read on every check.
  test "a release's health step is not read until the deploy it waits for is done, then counts only what came after it" do
    answers(ci: run_of("46", History::RUNNING, Time.current), status: "web is deploying", logs: "GET /up 200")
    start!(release_steps)
    watch = @conversation.chat.watches.sole
    run, deploy, health = watch.steps.to_a

    assert_equal [ [], [ run.position ], [ deploy.position ] ], [ run.waits_for, deploy.waits_for, health.waits_for ]
    check!(watch)

    assert_equal [ Step::STATUS_RUNNING, Step::STATUS_WAITING, Step::STATUS_WAITING ], watch.steps.reload.map(&:status)
    assert_equal "Waiting for GitHub release run.", Chat::Watch::Shown.step_line(watch.steps.second)
    assert_equal "Waiting for Web runs the release.", Chat::Watch::Shown.step_line(watch.steps.third)
    assert_not read?("describe_resource"), "a step whose prerequisite still runs is not read"
    assert_not read?("search_logs")

    answers(ci: run_of("46", History::SUCCEEDED, 2.minutes.ago, finished: 1.minute.ago), status: "web is serving", logs: "GET /up 200")
    travel(1.minute) { check!(watch) }

    deploy.reload
    assert_equal Step::STATUS_SUCCEEDED, deploy.status
    before, logs = @read.select { |name, _| name == "search_logs" }.map(&:last).partition { |given| given["end"].present? }
    assert logs.any?, "the health step starts once the deploy it waits for is done"
    assert(logs.all? { |given| Time.zone.parse(given["start"].to_s) == deploy.finished_at.change(usec: 0) }, "its logs are read only from when the deploy finished")
    assert_equal [ (deploy.finished_at.change(usec: 0)).utc.iso8601 ], before.uniq.map { |given| given["end"] }, "one read of what was logging before it, unfiltered"
    assert_nil before.uniq.sole["text"]
  end

  test "steps that wait for nothing are read at once, side by side" do
    answers(status: "web is serving", logs: "GET /up 200")
    start!([ status_step("Web up"), logs_step("Web healthy") ])
    check!(@conversation.chat.watches.sole)

    assert read?("describe_resource")
    assert read?("search_logs")
    assert_equal Chat::Watch::STATUS_SUCCEEDED, @conversation.chat.watches.sole.status
  end

  test "a step that waits for two others starts only once both succeeded" do
    answers(status: "web is deploying", logs: "nothing yet")
    start!([ status_step("Web up"), logs_step("Web healthy", done_when: "200"), status_step("Job up", resource: "job", waits_for: [ "Web up", 2 ]) ])
    watch = @conversation.chat.watches.sole
    assert_equal [ 0, 1 ], watch.steps.third.waits_for

    answers(status: "web is serving", logs: "nothing yet")
    check!(watch)
    assert_equal [ Step::STATUS_SUCCEEDED, Step::STATUS_WAITING, Step::STATUS_WAITING ], watch.steps.reload.map(&:status)
    assert_equal "Waiting for Web healthy.", Chat::Watch::Shown.step_line(watch.steps.third)

    answers(status: "web is serving", logs: "GET /up 200")
    check!(watch)
    assert_equal Step::STATUS_SUCCEEDED, watch.steps.reload.third.status
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "a failed step skips everything that waits for it, down the chain, and the watch ends on the real failure" do
    answers(ci: run_of("46", History::RUNNING, Time.current))
    start!(release_steps)
    watch = @conversation.chat.watches.sole

    answers(ci: run_of("46", History::FAILED, 2.minutes.ago, finished: 1.minute.ago))
    check!(watch)

    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert_equal [ Step::STATUS_FAILED, Step::STATUS_SKIPPED, Step::STATUS_SKIPPED ], watch.steps.map(&:status)
    assert_equal [ "Skipped because GitHub release run failed." ] * 2, watch.steps.drop(1).map { |step| Chat::Watch::Shown.step_line(step) }
    assert_match(/\AGitHub release run failed after/, watch.outcome)
    assert_match "Web runs the release and Web healthy were skipped, since they wait for it.", watch.outcome
    assert_not read?("describe_resource")
  end

  test "a step still waiting for another when the time runs out is skipped, naming what it waited for" do
    answers(ci: run_of("46", History::RUNNING, Time.current))
    start!(release_steps, minutes: 15)
    watch = @conversation.chat.watches.sole

    travel(16.minutes) { check!(watch) }

    assert_equal Chat::Watch::STATUS_TIMED_OUT, watch.reload.status
    assert_match "Web runs the release: Waiting for GitHub release run.", watch.outcome
    assert_equal [ "Skipped because GitHub release run did not finish within the time limit." ] * 2,
                 watch.steps.drop(1).map { |step| Chat::Watch::Shown.step_line(step) }
  end

  test "a step can only wait for a step before it" do
    answers(status: "web is serving")

    said = Conversation::Watches.start(@turn, watch_of([ status_step("Web up", waits_for: [ "Job up" ]), status_step("Job up", resource: "job") ]))
    assert_match "Nothing was started. Web up waits for Job up, which comes after it. A step waits only for steps before it.", said

    said = Conversation::Watches.start(@turn, watch_of([ status_step("Web up", waits_for: [ "Web up" ]) ]))
    assert_match "Web up waits for itself", said

    said = Conversation::Watches.start(@turn, watch_of([ status_step("Web up", waits_for: [ "Deploy" ]) ]))
    assert_match "Web up waits for Deploy, which is not one of its steps.", said
    assert_not Chat::Watch.exists?(workspace_id: @workspace.id)
  end

  test "a step can wait for a step the watch already has when it joins it" do
    answers(status: "web is deploying")
    start!([ status_step("Web up") ])
    watch = @conversation.chat.watches.sole

    said = Conversation::Watches.start(@turn, watch_of([ logs_step("Web healthy", waits_for: [ "Web up" ]) ]).merge("add_to" => watch.id))

    assert_match "Added Web healthy", said
    assert_equal [ watch.steps.first.position ], watch.steps.reload.second.waits_for
  end

  test "a step waiting for another is not handed back while that one runs, and is from when it finished" do
    answers(ci: [ run_of("46", History::RUNNING, Time.current), old_deploy ], status: "web is deploying")
    start!([ status_step("Web up", done_when: "never"), run_step,
             { "label" => "Deploy run", "capability" => "run_history", "resource" => "firefight", "name" => "deploy", "waits_for" => [ "GitHub release run" ] } ],
           minutes: 60)
    watch = @conversation.chat.watches.sole

    travel(10.minutes) { check!(watch) }
    assert_equal Step::STATUS_WAITING, watch.steps.reload.third.status
    assert_not watch.updates.exists?(kind: Chat::Watch::Update::KIND_HANDED_BACK)

    answers(ci: [ run_of("46", History::SUCCEEDED, Time.current, finished: Time.current + 10.minutes), old_deploy ], status: "web is deploying")
    travel(10.minutes) { check!(watch) }
    travel(14.minutes) { check!(watch) }

    assert_equal Step::STATUS_REPAIRING, watch.steps.reload.third.status, "an unrelated step still going does not hold it back"
  end

  test "a run step that waits for another follows only a run that started after that one began" do
    started = 3.minutes.ago
    answers(ci: [ run_of("46", History::SUCCEEDED, started, finished: 1.minute.ago), run_of("45", History::SUCCEEDED, started - 2.minutes, finished: started, name: "deploy") ])
    start!([ run_step, { "label" => "Deploy run", "capability" => "run_history", "resource" => "firefight", "name" => "deploy", "waits_for" => [ 1 ] } ])
    watch = @conversation.chat.watches.sole

    check!(watch)

    assert_equal [ Step::STATUS_SUCCEEDED, Step::STATUS_WAITING ], watch.steps.reload.map(&:status), "run #45 began before the step it waits for"

    answers(ci: [ run_of("47", History::RUNNING, started + 1.minute, name: "deploy"), run_of("46", History::SUCCEEDED, started, finished: 1.minute.ago) ])
    check!(watch)
    assert_equal [ "run-47", Step::STATUS_RUNNING ], [ watch.steps.reload.second.followed_run_id, watch.steps.second.status ]
  end

  test "a reading that shows failed is read once more before it ends the watch" do
    answers(status: "web crashed")
    start!([ status_step("Web up", failed_when: "crashed") ])
    watch = @conversation.chat.watches.sole

    check!(watch)
    assert_equal [ Chat::Watch::STATUS_ACTIVE, Step::STATUS_WAITING ], [ watch.reload.status, watch.steps.sole.status ]

    answers(status: "web is serving")
    check!(watch)
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status, "a second reading that disagrees wins"

    start!([ status_step("Job up", resource: "job", failed_when: "crashed") ], title: "job", separate: true)
    job = @conversation.chat.watches.find_by!(title: "job")
    answers(status: "job crashed")
    2.times { check!(job) }
    assert_equal [ Chat::Watch::STATUS_FAILED, Step::STATUS_FAILED ], [ job.reload.status, job.steps.sole.status ]
  end

  test "a logs step fails only on a line at error level, never on a warning or an instance stopping cleanly" do
    warning = %(job-1 {"level":"warn","message":"node failed: bad option"}\njob-1 {"level":"info","message":"exit code 0"})
    answers(logs: warning)
    start!([ logs_step("Job healthy", resource: "job", done_when: "Performed", failed_when: "exit code") ])
    watch = @conversation.chat.watches.sole

    2.times { check!(watch) }
    assert_equal Step::STATUS_WAITING, watch.steps.sole.reload.status

    answers(logs: %(job-2 {"level":"error","message":"exit code 1, boot failed"}))
    2.times { check!(watch) }
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
  end

  test "a logs step that waits for a deploy knows which sources were already logging before it began" do
    answers(status: "web is deploying", logs: "web-old GET /up 200")
    start!([ status_step("Web up"), logs_step("Web healthy", waits_for: [ "Web up" ], done_when: "never") ])
    watch = @conversation.chat.watches.sole

    answers(status: "web is serving", logs: "web-old GET /up 200")
    check!(watch)

    assert_equal [ "web-old" ], watch.steps.reload.second.sources_before
  end

  test "an ending a later reading shows was wrong is reopened, with the steps it skipped" do
    answers(ci: run_of("46", History::RUNNING, Time.current))
    start!(release_steps)
    watch = @conversation.chat.watches.sole
    answers(ci: run_of("46", History::FAILED, 2.minutes.ago, finished: 1.minute.ago))
    check!(watch)
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    clear_enqueued_jobs

    said = Conversation::Tools::RepairWatch.new(@turn).call(**{ "watch" => watch.id, "step" => "GitHub release run", "reopen" => true,
                                                                "why" => "The run was re-run and is going again." })

    assert_match "Reopened GitHub release run", said
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status
    assert_nil watch.finished_at
    assert_equal [ Step::STATUS_WAITING ] * 3, watch.steps.map(&:status)
    assert watch.expires_at > Time.current
    assert_equal "Reopened GitHub release run: The run was re-run and is going again.", watch.updates.find_by!(kind: Chat::Watch::Update::KIND_REOPENED).text
    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ])
    ended = watch.updates.find_by!(kind: Chat::Watch::Update::KIND_ENDED)
    assert_equal Conversation::Watches::TONE_FAILED, Conversation::Watches.said(watch, ended).tone, "the line that said it failed still says so"
  end

  test "a step that succeeded on the wrong reading is reopened while its watch goes on" do
    answers(status: "web is serving", logs: "GET /up 200")
    start!([ logs_step("Web healthy"), status_step("Job up", resource: "job", done_when: "never") ])
    watch = @conversation.chat.watches.sole
    check!(watch)
    assert_equal Step::STATUS_SUCCEEDED, watch.steps.first.reload.status

    said = Conversation::Tools::RepairWatch.new(@turn).call(**{ "watch" => watch.id, "step" => "Web healthy", "reopen" => true,
                                                                "why" => "Those lines came from the old container." })

    assert_match "Reopened Web healthy", said
    assert_equal Step::STATUS_WAITING, watch.steps.first.reload.status
  end

  test "a stopped watch is not reopened, since a person ended it" do
    answers(status: "web is deploying")
    start!([ status_step("Web up") ])
    watch = @conversation.chat.watches.sole
    Conversation::Watches.stop!(watch, by: @alice)

    said = Conversation::Tools::RepairWatch.new(@turn).call(**{ "watch" => watch.id, "step" => "Web up", "reopen" => true, "why" => "Wrong." })

    assert_match "was stopped", said
    assert_equal Chat::Watch::STATUS_STOPPED, watch.reload.status
  end

  private

  def release_steps
    [ run_step, status_step("Web runs the release", waits_for: [ "GitHub release run" ]), logs_step("Web healthy", waits_for: [ "Web runs the release" ]) ]
  end

  def old_deploy = run_of("40", History::SUCCEEDED, 3.days.ago, finished: 3.days.ago + 5.minutes, name: "deploy")

  def run_step = { "label" => "GitHub release run", "capability" => "run_history", "resource" => "firefight", "name" => "release", "run" => "46" }

  def status_step(label, resource: "web", done_when: "serving", failed_when: nil, waits_for: nil)
    { "label" => label, "capability" => "resource_status", "resource" => resource, "done_when" => done_when, "failed_when" => failed_when,
      "waits_for" => waits_for }.compact
  end

  def logs_step(label, resource: "web", done_when: "200", failed_when: nil, waits_for: nil)
    { "label" => label, "capability" => "search_logs", "resource" => resource, "arguments" => { "minutes" => 5 }, "done_when" => done_when,
      "failed_when" => failed_when, "waits_for" => waits_for }.compact
  end

  def start!(steps, title: "the release", **options)
    said = Conversation::Watches.start(@turn, watch_of(steps, title: title, **options))
    assert_match "Started", said
  end

  def watch_of(steps, title: "the release", **options) = { "title" => title, "steps" => steps, **options.transform_keys(&:to_s) }

  def connect!(provider, name, tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: provider)
    integration.integration_environments.create!(credentials: { token: "x" }.to_json)
    tools.each { |tool| integration.tools.create!(name: tool, description: tool, read_only: true, enabled: true, params_schema: { "type" => "object" }) }
    integration
  end

  def place!(integration, kind, name, external_id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: integration.provider, account: "acme", kind: kind, external_id: external_id,
                                  name: name, integration_environment: integration.integration_environments.sole,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end

  # Each provider tool answers what is given, every call is noted, and a log answer is in the shared shape, one
  # source per line.
  def answers(ci: nil, status: nil, logs: nil)
    texts = { "describe_resource" => status, "search_logs" => logs && log_text(logs) }.compact
    Integrations::NativeExecutor.stubs(:call).with do |tool:, arguments:, **|
      @read << [ tool.name, arguments ]
      true
    end.returns({ "content" => [ { "type" => "text", "text" => "No log lines matched." } ] })
    texts.each do |name, text|
      Integrations::NativeExecutor.stubs(:call).with do |tool:, arguments:, **|
        @read << [ tool.name, arguments ] if tool.name == name
        tool.name == name
      end.returns({ "content" => [ { "type" => "text", "text" => text } ] })
    end
    return unless ci

    runs = Array(ci)
    Integrations::NativeExecutor.stubs(:call).with do |tool:, arguments:, **|
      @read << [ tool.name, arguments ] if tool.name == "ci_runs"
      tool.name == "ci_runs"
    end.returns(History.result(runs, what: "acme/firefight"))
  end

  def log_text(lines)
    at = Time.current.utc.iso8601
    shown = lines.lines.map(&:strip).map { |line| line.match?(/\A\S+-\S* /) ? "#{at} #{line}" : "#{at} web-1 #{line}" }
    "#{shown.size} log lines for web, newest first.\n#{shown.join("\n")}"
  end

  def read?(tool_name) = @read.any? { |name, _| name == tool_name }

  def run_of(number, status, started, finished: nil, name: "release")
    History::Run.new(id: "run-#{number}", number: number, name: name, status: status, started_at: started, finished_at: finished)
  end

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
