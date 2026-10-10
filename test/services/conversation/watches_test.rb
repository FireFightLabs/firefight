require "test_helper"

class Conversation::WatchesTest < ActiveSupport::TestCase
  include SlackClientStubHelper
  include ActiveJob::TestHelper

  History = Integrations::Capabilities::History

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @github = connect!("github", "GitHub", %w[ci_runs job_log ci_status])
    @render = connect!("render", "Render", %w[deploy_history search_logs describe_resource])
    @repository = place!(@github, ResourceMap::KIND_REPOSITORY, "firefight", "acme/firefight")
    @service = place!(@render, ResourceMap::KIND_SERVICE, "web", "srv-web")
    stub_post_message
  end

  test "the time limit is learned from the run history of whichever provider runs it, twice the usual" do
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "acme/firefight"))
    said = Conversation::Watches.start(@turn, watch_of([ release_step ]))

    watch = @conversation.chat.watches.sole
    assert_match "This usually takes about 18 minutes, I will watch for up to 40.", said
    assert_equal [ Chat::Watch::BASIS_HISTORY, 18.minutes.to_i ], [ watch.limit_basis, watch.usual_seconds ]
    assert_in_delta 40.minutes.from_now, watch.expires_at, 5.seconds

    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))
    Conversation::Watches.start(@turn, watch_of([ deploy_step ], title: "the web deploy"))

    deploy = @conversation.chat.watches.find_by!(title: "the web deploy")
    assert_equal [ Chat::Watch::BASIS_HISTORY, 4.minutes.to_i ], [ deploy.limit_basis, deploy.usual_seconds ]
    assert_in_delta 10.minutes.from_now, deploy.expires_at, 5.seconds
  end

  test "a limit the person asked for wins, at most a day, and memory or the default stand in when history has nothing" do
    answers("ci_runs" => History.result([], what: "acme/firefight"))

    assert_match "as you asked", Conversation::Watches.start(@turn, watch_of([ release_step ], minutes: 5000, title: "asked"))
    assert_in_delta 24.hours.from_now, @conversation.chat.watches.find_by!(title: "asked").expires_at, 5.seconds

    assert_match "From what I remember this takes about 20 minutes, so I will watch for up to 40.",
                 Conversation::Watches.start(@turn, watch_of([ release_step ], expected_minutes: 20, title: "remembered"))
    assert_match "I have no history of how long this takes, so I will watch for up to 1 hour",
                 Conversation::Watches.start(@turn, watch_of([ release_step ], title: "unknown"))
  end

  test "a provider that keeps no run history says so, and nothing is started" do
    kubernetes = connect!("kubernetes", "Kubernetes", %w[workload_status])
    place!(kubernetes, ResourceMap::KIND_SERVICE, "api", "default/deployment/api")

    said = Conversation::Watches.start(@turn, watch_of([ { "label" => "API rollout", "capability" => "run_history", "resource" => "api" } ]))

    assert_match "Nothing was started", said
    assert_match "Kubernetes keeps no run history Halon can read. #{IntegrationProvider.find('kubernetes').history_note}", said
    assert_not Chat::Watch.exists?(workspace_id: @workspace.id)
  end

  test "each milestone is said once, in the chat and the asker's direct messages, and the watch ends once everything succeeded" do
    start_release_watch(report_start: true)
    watch = @conversation.chat.watches.sole
    started = Time.current

    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, started) ], what: "repo"))
    Slack::Client.expects(:post_message).with { |channel:, **| channel == @alice.platform_user_id }.once.returns(ts: "1", channel: "D1")
    2.times { check!(watch) }

    assert_equal [ "Release run #46 started." ], watch.updates.reload.map(&:text)

    answers("ci_runs" => History.result([ run_of("46", History::SUCCEEDED, started, finished: started + 17.minutes) ], what: "repo"))
    Slack::Client.expects(:post_message).twice.returns(ts: "2", channel: "D1")
    2.times { check!(watch) }

    assert_equal "Release run #46 succeeded after 17 minutes.", watch.updates.reload.second.text
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_match "Done: release run #46", watch.outcome
    assert_equal 3, watch.updates.count
  end

  test "a failed run ends the watch with why, read only from its log" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    started = Time.current
    Investigation.stubs(:unavailable_reason).returns(nil)
    answers("ci_runs" => History.result([ run_of("46", History::FAILED, started, finished: started + 6.minutes, url: "https://github.com/acme/firefight/actions/runs/46") ], what: "repo"),
            "job_log" => { "content" => [ { "type" => "text", "text" => "Run tests\nFAILED test/models/user_test.rb: expected 2 got 3" } ] })
    FirefightAi::WatchJudge.any_instance.expects(:why_failed).with { |evidence:, **| evidence.include?("expected 2 got 3") }
                           .returns("The user model test failed: expected 2 got 3.")

    check!(watch)

    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert_equal "Release run #46 failed after 6 minutes, so I stopped watching release run #46. The user model test failed: expected 2 got 3. " \
                 "https://github.com/acme/firefight/actions/runs/46", watch.outcome
    assert_equal [ Chat::Watch::Update::KIND_ENDED ], watch.updates.map(&:kind)
    assert Ability::Invocation.where(workspace: @workspace, action_key: "github.job_log").exists?
  end

  test "a run that goes well past its usual time is said to be slow, once" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))
    check!(watch)

    travel 30.minutes do
      2.times { check!(watch) }
    end

    assert_equal [ "Release run #46 is taking longer than usual, 30 minutes so far where it usually takes 18 minutes." ], watch.updates.reload.map(&:text)
  end

  test "at its time limit it stops and says what it last saw" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))
    check!(watch)

    travel 41.minutes do
      check!(watch)
    end

    assert_equal Chat::Watch::STATUS_TIMED_OUT, watch.reload.status
    assert_match "the time limit. Last I saw: Release run #46: - #46 release: running", watch.outcome
  end

  test "stopping says so once, and in a personal chat only whoever asked may" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert_equal "Only #{@alice.display_name} or whoever this chat belongs to can stop this watch.",
                 Conversation::Watches.stop!(watch, by: workspace_memberships(:bob_workspace_one))
    assert_nil Conversation::Watches.stop!(watch, by: @alice)
    assert_equal Chat::Watch::NOTHING_TO_STOP, Conversation::Watches.stop!(watch, by: @alice)

    assert_equal [ Chat::Watch::STATUS_STOPPED, @alice ], [ watch.reload.status, watch.stopped_by ]
    assert_equal [ "#{@alice.display_name} stopped the watch on release run #46." ], watch.updates.map(&:text)
  end

  test "anyone in the channel or thread a watch reports to may stop it" do
    thread = Conversation.create!(workspace: @workspace, kind: Conversation::KIND_CHANNEL, channel_id: "C0WATCH", thread_id: "1700000000.000100",
                                  started_by: @alice, max_turns: 5, max_spend_cents: 100)
    @turn = Conversation::Turn.new(thread, asker: @alice)
    start_release_watch
    watch = thread.chat.watches.sole
    bob = workspace_memberships(:bob_workspace_one)

    assert_nil Conversation::Watches.stop!(watch, by: bob)
    assert_equal [ Chat::Watch::STATUS_STOPPED, bob ], [ watch.reload.status, watch.stopped_by ]
  end

  test "a watch reads only what the asker may, and stops following a read taken away from them" do
    key = api_keys(:full_access_key)
    turn = Conversation::Turn.new(Conversation.for_mcp!(workspace: @workspace, principal: key), asker: key)
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "repo"))

    refused = Conversation::Watches.start(turn, watch_of([ release_step ]))
    assert_match "Nothing was started", refused

    map = Ability::Action.lookup(Ability::Action.system_key(Ability::Action::RESOURCE_MAP, Ability::Action::ACTION_READ), @workspace)
    Ability::Grant.create!(workspace: @workspace, principal: key, action: map)
    grant = Ability::Grant.create!(workspace: @workspace, principal: key, action: tool(@github, "ci_runs").ability_action)
    bust!(key)
    started = Conversation::Watches.start(turn, watch_of([ release_step ]))
    assert_match "Started watching", started
    watch = Chat::Watch.find_by!(asker: key)

    grant.destroy!
    bust!(key)
    check!(watch)

    assert_match "I can no longer follow Release run #46.", watch.updates.reload.first.text
    assert_equal Chat::Watch::STATUS_STOPPED, watch.reload.status
    assert Ability::Invocation.where(workspace: @workspace, principal: key, decision: Ability::Invocation::DECISION_ALLOW, action_key: "github.ci_runs").exists?
  end

  test "a failed deploy reads the app's log first unless its step is a build, a test or CI run" do
    asked = []
    reader = stub
    reader.stubs(:read).with { |_capability, given| asked << given["stream"] }.returns(stub(failed?: true))
    call = stub(resource: stub(kind: ResourceMap::KIND_SERVICE, id: "web"))

    Conversation::Watches.log_evidence(stub(label: "Deploy pricing service"), stub(started_at: nil), reader, call)
    assert_equal [ Integrations::Capabilities::STREAM_APP, Integrations::Capabilities::STREAM_BUILD ], asked

    asked.clear
    Conversation::Watches.log_evidence(stub(label: "Run the tests"), stub(started_at: nil), reader, call)
    assert_equal [ Integrations::Capabilities::STREAM_BUILD ], asked
  end

  test "more time is given up to a day from when it started, and only while it goes" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    extend_watch = Conversation::Tools::ExtendWatch.new(@turn)

    assert_match "now watched for up to 1 hr 30 min", extend_watch.call(**{ "watch" => watch.id, "minutes" => 90 })
    assert_equal [ watch.created_at + 90.minutes, Chat::Watch::BASIS_ASKED ], [ watch.reload.expires_at, watch.limit_basis ]
    assert_equal "Say how many minutes, more than the 90 it has now.", extend_watch.call(**{ "watch" => watch.id, "minutes" => 30 })
    assert_equal watch.created_at + 90.minutes, watch.reload.expires_at
    extend_watch.call(**{ "watch" => watch.id, "minutes" => 5000 })
    assert_equal watch.created_at + 24.hours, watch.reload.expires_at

    Conversation::Watches.stop!(watch, by: @alice)
    assert_equal Chat::Watch::NOTHING_TO_STOP, extend_watch.call(**{ "watch" => watch.id, "minutes" => 2000 })
  end

  test "stop_watch stops the watch it is named by, the way the model calls it" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert_match "Stopped watching", Conversation::Tools::StopWatch.new(@turn).call(**{ "watch" => watch.id })
    assert_equal Chat::Watch::STATUS_STOPPED, watch.reload.status
  end

  test "a check another worker holds is left alone, a claim a dead worker left lapses, and a milestone is claimed once" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert watch.claim_check!
    assert_not watch.claim_check!
    travel Chat::Watch::CLAIM_LAPSES + 1.second do
      assert watch.claim_check!
    end

    step = watch.steps.sole
    assert step.finished!(Chat::Watch::Step::STATUS_SUCCEEDED)
    assert_not Chat::Watch::Step.find(step.id).finished!(Chat::Watch::Step::STATUS_FAILED)
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
  end

  test "a chat in a Slack thread is told in the thread, and the asker by direct message unless the thread is one" do
    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "111.1")
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).with { |channel:, thread_ts: nil, **| channel == "C1" && thread_ts == "111.1" }.returns(ts: "1", channel: "C1")
    Slack::Client.expects(:post_message).with { |channel:, blocks:, **| channel == @alice.platform_user_id && actions_of(blocks) == [ Identifiers::WATCH_STOP ] }
                 .returns(ts: "2", channel: "D1")
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    @conversation.update!(channel_id: "D42")
    Slack::Client.expects(:post_message).with { |channel:, **| channel == "D42" }.once.returns(ts: "3", channel: "D42")
    Conversation::Watches.tell!(watch.reload, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 succeeded.")
  end

  test "a dashboard chat's direct message offers to open the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).with(@conversation.id).returns("https://firefight.test/app/agent/#{@conversation.id}")
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).with { |channel:, blocks:, **| channel == @alice.platform_user_id && blocks.last[:type] == "actions" }
                 .returns(ts: "1", channel: "D1")

    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")
  end

  test "a live update from a connection wakes the watches that read through it" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    row = @github.integration_environments.sole

    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ]) do
      Integrations::MapEvents.receive!(row, [ ResourceMap::Event.new(id: "e1", action: ResourceMap::Event::UPDATED, at: Time.current) ])
    end
  end

  test "Halon hears what its watches said once, at its next turn" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    assert_match "release run #46: Release run #46 started.", Conversation::Watches.untold_note(@conversation.chat)
    assert_nil Conversation::Watches.untold_note(@conversation.chat)
  end

  test "a workspace keeps only so many watches going at once" do
    answers("ci_runs" => History.result([], what: "repo"))
    Chat::Watch.stubs(:workspace_active).returns(stub(count: Chat::Watch::ACTIVE_LIMIT))

    assert_match "already has #{Chat::Watch::ACTIVE_LIMIT} watches going", Conversation::Watches.start(@turn, watch_of([ release_step ]))
  end

  test "a reading that is not a run ends on the words it was given, and asks no model while nothing changed" do
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying, updated 2 minutes ago" } ] })
    Conversation::Watches.start(@turn, watch_of([ { "label" => "web back", "capability" => "resource_status", "resource" => "web",
                                                     "done_when" => "live", "goal" => "web is live on the new version" } ], title: "web"))
    watch = @conversation.chat.watches.sole
    Investigation.stubs(:unavailable_reason).returns(nil)
    FirefightAi::WatchJudge.any_instance.expects(:reading).once.returns(FirefightAi::WatchJudge::Reading.new(state: "running", said: "Still deploying.", parts: []))

    check!(watch)
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying, updated 3 minutes ago" } ] })
    check!(watch)
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is live" } ] })
    check!(watch)

    assert_equal "web back: done.", watch.updates.reload.first.text
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "the first job that fails inside a run is said at once with why from its own log, while the run still goes" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    answers("ci_runs" => History.result(finished_runs("Release", 7.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ { "label" => "GitHub Release workflow", "capability" => "run_history", "resource" => "firefight",
                                                     "name" => "Release", "run" => "37831890378" } ],
                                                 purpose: "get GitHub releases deploying through the Northflank webhook again"))
    watch = @conversation.chat.watches.sole
    started = Time.current
    failed_job = History::Part.new(
      id: "113499155075", name: "trigger-northflank", status: History::FAILED, started_at: started + 2.seconds, finished_at: started + 6.seconds,
      url: "https://github.com/acme/firefight/actions/runs/37831890378/job/113499155075", detail: "at Notify Northflank of the release",
      log: { History::LOG_TOOL => "job_log", History::LOG_ARGUMENTS => { "repo" => "acme/firefight", "job_id" => 113499155075 } }
    )
    tagging = History::Part.new(id: "113499083801", name: "tag", status: History::SUCCEEDED, started_at: started, finished_at: started + 30.seconds)
    running = History::Run.new(id: "37831890378", number: "50", name: "Release", status: History::RUNNING, started_at: started, parts: [ tagging, failed_job ])
    answers("ci_runs" => History.result([ running ], what: "repo"),
            "job_log" => { "content" => [ { "type" => "text", "text" => "Notify Northflank of the release\n\"name\" with value \"v0.0.14\" fails to match the required pattern\ncurl: (22) The requested URL returned error: 400" } ] })
    FirefightAi::WatchJudge.any_instance.expects(:why_failed).once
                           .with { |what:, evidence:| what.include?("trigger-northflank") && evidence.include?("fails to match the required pattern") }
                           .returns("Northflank refused the webhook because the name v0.0.14 has dots it does not take.")
    FirefightAi::WatchJudge.any_instance.expects(:standing).once
                           .with { |purpose:, happened:| purpose.include?("Northflank webhook") && happened.include?("trigger-northflank failed") }
                           .returns("The GitHub path is still broken. Next I would change the name the release sends, shall I?")

    2.times { check!(watch) }

    said, progress = watch.updates.reload.order(:created_at).to_a
    assert_equal [ Chat::Watch::Update::KIND_PART_FAILED, Chat::Watch::Update::KIND_PROGRESS ], [ said.kind, progress.kind ]
    assert_equal "GitHub Release workflow: tag passed.", progress.text, "the job that passed is said once, the failed one only with its reason"
    assert_equal "GitHub Release workflow: trigger-northflank failed at Notify Northflank of the release, 4 seconds in. Northflank refused the webhook " \
                 "because the name v0.0.14 has dots it does not take. https://github.com/acme/firefight/actions/runs/37831890378/job/113499155075 " \
                 "The GitHub path is still broken. Next I would change the name the release sends, shall I?", said.text
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status
    assert_equal "trigger-northflank", watch.steps.sole.failed_part
    assert_match "trigger-northflank failed.", Chat::Watch::Shown.step_state(watch.steps.sole)
    invoked = Ability::Invocation.where(workspace: @workspace, action_key: "github.job_log")
    assert_equal [ AbilityGateway::SOURCE_WATCH ], invoked.map(&:source).uniq
    assert_match "(for: get GitHub releases deploying through the Northflank webhook again)", Conversation::Watches.untold_note(@conversation.chat)
  end

  test "a followed run is read by its id, which brings its jobs" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))
    check!(watch)
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool.name == "ci_runs" && arguments["run"] == "run-46" }
                                .returns(History.result([ run_of("46", History::RUNNING, Time.current).with(parts: []) ], what: "repo"))

    check!(watch)
  end

  test "a step can read any read tool Halon holds by name, a tool that can change things only with a read" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    northflank.tools.create!(name: "api_request", description: "Any call to Northflank's API", read_only: false, enabled: true,
                             params_schema: { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } })
    Ability::Approval.stubs(:self_approvable_by?).returns(false)
    Integration::Tool.any_instance.stubs(:callable_by?).returns(true)
    run = { "content" => [ { "type" => "text", "text" => '{"data":{"id":"90a3ba2f","status":"running"}}' } ] }
    answers("api_request" => run)
    step = { "label" => "Northflank release workflow", "tool" => "northflank_api_request",
             "arguments" => { "method" => "GET", "path" => "workflows/release/runs/90a3ba2f" },
             "done_when" => '"status":"success"', "failed_when" => '"status":"failure"' }

    refused = Conversation::Watches.start(@turn, watch_of([ step.merge("arguments" => { "method" => "POST", "path" => "workflows/release/runs" }) ], title: "posted"))
    assert_match "Nothing was started", refused
    assert_match "only reads, so its method must be GET", refused

    Investigation.stubs(:unavailable_reason).returns("unavailable")
    assert_match "Started watching", Conversation::Watches.start(@turn, watch_of([ step ], title: "the release workflow", purpose: "ship main"))
    watch = @conversation.chat.watches.sole
    assert_equal [ Chat::Watch::Step::READ_TOOL, "northflank_api_request" ], [ watch.steps.sole.capability, watch.steps.sole.tool_name ]
    check!(watch)
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status

    answers("api_request" => { "content" => [ { "type" => "text", "text" => '{"data":{"id":"90a3ba2f","status":"failure"}}' } ] })
    Investigation.stubs(:unavailable_reason).returns("unavailable")
    check!(watch)

    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert_match "Northflank release workflow failed", watch.outcome
    assert_match "This was for: ship main", watch.outcome
    calls = Ability::Invocation.where(workspace: @workspace, action_key: "northflank.api_request", decision: Ability::Invocation::DECISION_ALLOW)
    assert calls.all? { |invocation| invocation.source == AbilityGateway::SOURCE_WATCH }
    assert calls.any?
  end

  test "a read tool step moves to running once its reading shows the run began, and says each job as it starts or passes, once per check" do
    northflank_api!
    Investigation.stubs(:unavailable_reason).returns(nil)
    step = { "label" => "Northflank release workflow", "tool" => "northflank_api_request", "done_when" => '"status":"success"',
             "arguments" => { "method" => "GET", "path" => "workflows/release/runs/release-v0-0-15" } }
    answers("api_request" => northflank_run("queued"))
    Conversation::Watches.start(@turn, watch_of([ step ], title: "the release"))
    watch = @conversation.chat.watches.sole
    passed = ->(*names) { names.map { |name| [ name, FirefightAi::Schemas::WatchReading::PART_PASSED ] } }
    running = ->(name) { [ [ name, FirefightAi::Schemas::WatchReading::PART_RUNNING ] ] }
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::NOT_STARTED, said: "Queued.", parts: [])
    ).then.returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::RUNNING, said: "Running.", parts: passed.call("tag") + running.call("trigger-northflank"))
    ).then.returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::RUNNING, said: "Running.",
                                           parts: passed.call("tag", "trigger-northflank") + running.call("build-images"))
    )

    check!(watch)
    followed = watch.steps.sole
    assert_equal [ Chat::Watch::Step::STATUS_WAITING, "Waiting for it to start." ], [ followed.reload.status, Chat::Watch::Shown.step_state(followed) ]
    assert_empty watch.updates.reload

    answers("api_request" => northflank_run("running", jobs: 1))
    check!(watch)
    assert_equal Chat::Watch::Step::STATUS_RUNNING, followed.reload.status
    assert followed.started_at
    assert_equal "Running. Passed so far: tag.", Chat::Watch::Shown.step_state(followed)
    assert_equal [ "Northflank release workflow: tag passed, trigger-northflank running." ], watch.updates.reload.map(&:text)

    answers("api_request" => northflank_run("running", jobs: 2))
    check!(watch)
    assert_equal "Northflank release workflow: trigger-northflank passed, build-images running.", watch.updates.reload.order(:created_at).last.text
    assert_equal 2, watch.updates.where(kind: Chat::Watch::Update::KIND_PROGRESS).count, "one line per check, never one per job"

    answers("api_request" => northflank_run("success", jobs: 3))
    check!(watch)
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_equal [ Chat::Watch::Update::KIND_PROGRESS, Chat::Watch::Update::KIND_PROGRESS, Chat::Watch::Update::KIND_MILESTONE, Chat::Watch::Update::KIND_ENDED ],
                 watch.updates.order(:created_at).map(&:kind)
    watch.updates.each { |update| assert_no_match(/\u2014|;/, update.text) }
  end

  test "a run Halon names is followed by its id from the first check, and its jobs are said as they pass, then the end" do
    Investigation.stubs(:unavailable_reason).returns("unavailable")
    id = "37853417403"
    answers("ci_runs" => History.result(finished_runs("Release", 7.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "Release",
                                                     "run" => id } ], title: "the release run"))
    watch = @conversation.chat.watches.sole
    started = Time.current
    part = ->(name, status) { History::Part.new(id: name, name: name, status: status, started_at: started) }
    release = ->(status, parts) { History::Run.new(id: id, number: "51", name: "Release", status: status, started_at: started, parts: parts) }
    asked = []
    reading = lambda do |runs|
      Integrations::NativeExecutor.stubs(:call).with { |tool:, arguments:, **| tool.name == "ci_runs" && asked << arguments["run"] }
                                  .returns(History.result(runs, what: "repo"))
    end

    reading.call([])
    check!(watch)
    assert_equal Chat::Watch::Step::STATUS_WAITING, watch.steps.sole.status

    reading.call([ release.call(History::RUNNING, [ part.call("tag", History::SUCCEEDED), part.call("trigger-northflank", History::RUNNING) ]) ])
    check!(watch)
    reading.call([ release.call(History::RUNNING, [ part.call("tag", History::SUCCEEDED), part.call("trigger-northflank", History::SUCCEEDED) ]) ])
    check!(watch)
    reading.call([ release.call(History::SUCCEEDED, [ part.call("tag", History::SUCCEEDED), part.call("trigger-northflank", History::SUCCEEDED) ])
                     .with(finished_at: started + 4.minutes) ])
    check!(watch)

    assert_equal id, asked.first, "the first read asks for that run"
    assert_equal [ id ], asked.drop(asked.index(nil) + 1).uniq, "the recent runs are read only while it is not there yet, then always that run"
    assert_equal [ "Release run: tag passed, trigger-northflank running.", "Release run: trigger-northflank passed.", "Release run succeeded after 4 minutes." ],
                 watch.updates.order(:created_at).first(3).map(&:text)
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "a run that never shows up in its history is handed back to Halon to re-plan, once, while a step before it still goes it waits" do
    answers("ci_runs" => History.result(finished_runs("release", 7.minutes), what: "repo"),
            "deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))
    Investigation.stubs(:unavailable_reason).returns("unavailable")
    Conversation::Watches.start(@turn, watch_of([ release_step, deploy_step ], purpose: "release main"))
    watch = @conversation.chat.watches.sole
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"),
            "deploy_history" => History.result([], what: "web"))

    travel 5.minutes do
      assert_no_enqueued_jobs(only: ConversationReplyJob) { check!(watch) }
    end

    answers("ci_runs" => History.result([ run_of("46", History::SUCCEEDED, Time.current, finished: 6.minutes.from_now) ], what: "repo"),
            "deploy_history" => History.result([], what: "web"))
    travel 6.minutes do
      check!(watch)
    end
    deploy = watch.steps.find_by!(label: "Web deploy")
    assert_equal Chat::Watch::Step::STATUS_WAITING, deploy.status

    travel 10.minutes do
      assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, @alice.id, nil, deploy.id ]) { check!(watch) }
      assert_no_enqueued_jobs(only: ConversationReplyJob) { check!(watch) }
    end

    assert_equal Chat::Watch::Step::STATUS_UNFOLLOWABLE, deploy.reload.status
    assert_includes watch.updates.reload.map(&:text), "I could not find a run of Web deploy in its history after 4 minutes, so I am finding another way to follow it."
    note = Conversation::Watches.hand_back_note(deploy)
    assert_match "It was started for: release main", note
    assert_match "Change nothing in this turn", note
  end

  test "a watch's database read goes to the primary unless its step asked for a replica, as Halon's own reads do" do
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    planetscale.integration_environments.create!
    planetscale.tools.create!(name: "planetscale_execute_read_query", description: "Runs a read", read_only: true, enabled: true,
                              params_schema: { "type" => "object", "properties" => { "query" => { "type" => "string" }, "use_replica" => { "type" => "boolean" } } })
    Integration::Tool.any_instance.stubs(:callable_by?).returns(true)
    sent = []
    Integrations::McpExecutor.stubs(:call).with { |arguments:, **| sent << arguments }
                             .returns("content" => [ { "type" => "text", "text" => '{"rows":[{"count":"1"}]}' } ])
    step = { "label" => "Workspaces", "tool" => "planetscale_planetscale_execute_read_query", "arguments" => { "query" => "select count(*) from workspaces" },
             "done_when" => '"count":"2"' }
    Investigation.stubs(:unavailable_reason).returns("unavailable")

    assert_match "Started watching", Conversation::Watches.start(@turn, watch_of([ step ], title: "primary"))
    check!(@conversation.chat.watches.find_by!(title: "primary"))
    replica = step.merge("arguments" => { "query" => "select 2", "use_replica" => true })
    assert_match "Started watching", Conversation::Watches.start(@turn, watch_of([ replica ], title: "replica"))
    check!(@conversation.chat.watches.find_by!(title: "replica"))

    assert sent.any?
    assert(sent.all? { |arguments| arguments.key?("use_replica") })
    assert_equal [ false ], sent.select { |arguments| arguments["query"].include?("workspaces") }.map { |arguments| arguments["use_replica"] }.uniq
    assert_equal [ true ], sent.select { |arguments| arguments["query"] == "select 2" }.map { |arguments| arguments["use_replica"] }.uniq
  end

  private

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

  def tool(integration, name) = integration.tools.find_by!(name: name)

  def northflank_api!
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    northflank.tools.create!(name: "api_request", description: "Any call to Northflank's API", read_only: false, enabled: true,
                             params_schema: { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } })
    Ability::Approval.stubs(:self_approvable_by?).returns(false)
    Integration::Tool.any_instance.stubs(:callable_by?).returns(true)
  end

  def northflank_run(status, jobs: 0)
    { "content" => [ { "type" => "text", "text" => { "data" => { "name" => "release-v0-0-15", "status" => status, "jobs_done" => jobs } }.to_json } ] }
  end

  def bust!(principal)
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end

  NO_LINES = { "content" => [ { "type" => "text", "text" => "No log lines matched." } ] }.freeze

  # Each provider tool answers what is given for it, and any other says it found nothing. A later call wins.
  def answers(by_tool)
    Integrations::NativeExecutor.stubs(:call).returns(NO_LINES)
    by_tool.each { |name, answer| Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == name }.returns(answer) }
  end

  def finished_runs(name, took)
    [ 5, 4, 3 ].map do |days|
      started = days.days.ago
      run_of("#{days}0", History::SUCCEEDED, started, finished: started + took, name: name)
    end
  end

  def run_of(number, status, started, finished: nil, name: "release", url: nil)
    History::Run.new(id: "run-#{number}", number: number, name: name, status: status, started_at: started, finished_at: finished, url: url)
  end

  def release_step(report_start: false)
    { "label" => "Release run #46", "capability" => "run_history", "resource" => "firefight", "name" => "release", "run" => "46",
      "report_start" => report_start }
  end

  def deploy_step = { "label" => "Web deploy", "capability" => "run_history", "resource" => "web", "name" => "deploy" }

  def watch_of(steps, title: "release run #46", **options)
    { "title" => title, "steps" => steps, **options.transform_keys(&:to_s) }
  end

  def start_release_watch(report_start: false)
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ release_step(report_start: report_start) ]))
  end

  # The buttons on a message, by action id or by address for a link.
  def actions_of(blocks) = blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |button| button[:action_id] || button[:url] } }

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
