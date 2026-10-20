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
    stub_update_message
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
    modal = connect!("modal", "Modal", %w[describe_app])
    place!(modal, ResourceMap::KIND_SERVICE, "api", "api")

    said = Conversation::Watches.start(@turn, watch_of([ { "label" => "API rollout", "capability" => "run_history", "resource" => "api" } ]))

    assert_match "Nothing was started", said
    assert_match "Modal keeps no run history Halon can read. #{IntegrationProvider.find('modal').history_note}", said
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
    Slack::Client.expects(:update_message).with { |channel:, ts:, **| channel == "D1" && ts == "1" }.twice
    Slack::Client.expects(:post_message).with { |channel:, thread_ts: nil, **| channel == @alice.platform_user_id && thread_ts.nil? }.once.returns(ts: "2", channel: "D1")
    2.times { check!(watch) }

    assert_equal "Release run #46 succeeded after 17 minutes.", watch.updates.reload.second.text
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_match(/\ADone in /, watch.outcome, "the watch's name already heads the line wherever it shows")
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
    assert_equal "Release run #46 failed after 6 minutes, so I stopped the watch \"release run #46\". The user model test failed: expected 2 got 3. " \
                 "https://github.com/acme/firefight/actions/runs/46", watch.outcome
    assert_equal [ Chat::Watch::Update::KIND_ENDED ], watch.updates.map(&:kind)
    assert_equal "Release run #46 failed after 6 minutes. The user model test failed: expected 2 got 3. https://github.com/acme/firefight/actions/runs/46",
                 Chat::Watch::Shown.why(watch), "the card says why it failed"
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

  test "a run held for a person past its usual time is said to wait, never to be slow" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("ci_runs" => History.result([ run_of("46", History::WAITING, Time.current) ], what: "repo"))
    check!(watch)

    travel 30.minutes do
      2.times { check!(watch) }
    end

    assert_not watch.updates.reload.any? { |update| update.kind == Chat::Watch::Update::KIND_SLOW }
    assert watch.updates.any? { |update| update.text.include?(Chat::Watch::Step::PART_HELD) }
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
    assert_match "its time limit. Last I saw: Release run #46: - #46 release: running", watch.outcome
  end

  test "stopping says so once, and in a personal chat only whoever asked may" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert_equal "Only #{@alice.display_name} or whoever this chat belongs to can stop this watch.",
                 Conversation::Watches.stop!(watch, by: workspace_memberships(:bob_workspace_one))
    assert_nil Conversation::Watches.stop!(watch, by: @alice)
    assert_equal Chat::Watch::NOTHING_TO_STOP, Conversation::Watches.stop!(watch, by: @alice)

    assert_equal [ Chat::Watch::STATUS_STOPPED, @alice ], [ watch.reload.status, watch.stopped_by ]
    assert_equal [ "#{@alice.display_name} stopped the watch \"release run #46\"." ], watch.updates.map(&:text)
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
    assert_match "Started Watch", started
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

    Conversation::Watches.log_evidence(stub(label: "Deploy pricing service"), stub(started_at: nil, id: nil), reader, call)
    assert_equal [ Integrations::Capabilities::STREAM_APP, Integrations::Capabilities::STREAM_BUILD ], asked

    asked.clear
    Conversation::Watches.log_evidence(stub(label: "Run the tests"), stub(started_at: nil, id: nil), reader, call)
    assert_equal [ Integrations::Capabilities::STREAM_BUILD ], asked
  end

  test "a routed call carries a run by its whole id, as an argument or inside a script, never inside a longer one" do
    assert Conversation::Watches.carries_run?({ "run" => "12" }, "12")
    assert Conversation::Watches.carries_run?({ "code" => "request({ path: \"/deployments/ab-12\" })" }, "ab-12")
    assert_not Conversation::Watches.carries_run?({ "run" => "123" }, "12")
    assert_not Conversation::Watches.carries_run?({ "code" => "path /deployments/ab-123" }, "ab-12")
  end

  test "a failed run's build log is read by the run's own id, never only the newest" do
    asked = []
    reader = stub
    reader.stubs(:read).with { |_capability, given| asked << given.slice("stream", "deployment") }.returns(stub(failed?: true))
    call = stub(resource: stub(kind: ResourceMap::KIND_SERVICE, id: "web"))

    Conversation::Watches.log_evidence(stub(label: "Deploy pricing service"), stub(started_at: nil, id: "dep-42"), reader, call)
    assert_equal [ { "stream" => Integrations::Capabilities::STREAM_APP }, { "stream" => Integrations::Capabilities::STREAM_BUILD, "deployment" => "dep-42" } ], asked
  end

  test "more time is given up to a day from when it started, and only while it goes" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    extend_watch = Conversation::Tools::ExtendWatch.new(@turn)

    assert_match "now runs for up to 1 hr 30 min", extend_watch.call(**{ "watch" => watch.id, "minutes" => 90 })
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

    assert_match "Stopped the watch", Conversation::Tools::StopWatch.new(@turn).call(**{ "watch" => watch.id })
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

    other = @conversation.chat.watches.create!(workspace: @workspace, asker: @alice, title: "another", expires_at: 1.hour.from_now,
                                               limit_basis: Chat::Watch::BASIS_DEFAULT)
    @conversation.update!(channel_id: "D42")
    Slack::Client.expects(:post_message).with { |channel:, **| channel == "D42" }.once.returns(ts: "3", channel: "D42")
    Conversation::Watches.tell!(other, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 succeeded.")
  end

  test "a dashboard chat's direct message offers to open the chat, and a reply to it there is known to be about the watch" do
    Slack::DashboardUrl.stubs(:agent_chat).with(@conversation.id).returns("https://firefight.test/app/agent/#{@conversation.id}")
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).with { |channel:, blocks:, **| channel == @alice.platform_user_id && blocks.sole[:actions].last[:url].include?(@conversation.id) }
                 .returns(ts: "1", channel: "D1")

    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    assert_equal [ "D1", "1" ], watch.reload.values_at(:direct_card_channel_id, :direct_card_message_id)
    assert_match '"title": "release run #46"', Conversation::RepliedTo.context(@workspace, channel_id: "D1", message_id: "1", text: "is it done?")
  end

  test "each place gets one card, edited in place as the watch moves, and its end is also said in a short line of its own" do
    @conversation.update!(kind: Conversation::KIND_CHANNEL, channel_id: "C1", thread_id: "111.1")
    start_release_watch
    watch = @conversation.chat.watches.sole
    watch.update!(purpose: "Ship main")
    Slack::Client.expects(:post_message).with { |channel:, thread_ts: nil, **| channel == "C1" && thread_ts == "111.1" }.once.returns(ts: "1", channel: "C1")
    Slack::Client.expects(:post_message).with { |channel:, thread_ts: nil, **| channel == @alice.platform_user_id && thread_ts.nil? }.once.returns(ts: "2", channel: "D1")
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")
    assert_equal [ "C1", "1", "D1", "2" ], watch.reload.values_at(:thread_card_channel_id, :thread_card_message_id, :direct_card_channel_id, :direct_card_message_id)

    drawn = []
    Slack::Client.expects(:update_message).times(4).with { |channel:, ts:, blocks:, **| drawn << [ channel, ts, blocks.sole ] }
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_PROGRESS, "Release run: tag passed.")
    assert_equal [ [ "C1", "1" ], [ "D1", "2" ] ], drawn.map { |channel, ts, _| [ channel, ts ] }
    assert_equal [ ":eyes:  Ship main", "Watching", "Waiting for Release run #46 to start." ],
                 [ drawn.first.last.dig(:title, :text), drawn.first.last.dig(:subtitle, :text), drawn.first.last.dig(:body, :text) ]

    bob = workspace_memberships(:bob_workspace_one)
    ended = []
    Slack::Client.expects(:post_message).twice.with { |channel:, text:, thread_ts: nil, **| ended << [ channel, thread_ts, text ] }.returns(ts: "9", channel: "C1")
    assert_nil Conversation::Watches.stop!(watch.reload, by: bob)

    assert_equal [ "Stopped", "Stopped" ], drawn.last(2).map { |_, _, card| card.dig(:subtitle, :text) }
    assert(drawn.last(2).all? { |_, _, card| card[:actions].to_a.none? { |button| button[:action_id] == Identifiers::WATCH_STOP } })
    told = "Stopped: Ship main. Stopped by #{bob.display_name}."
    assert_equal [ [ "C1", "111.1", told ], [ @alice.platform_user_id, nil, told ] ], ended
  end

  test "a watch its asker stopped redraws its card and posts nothing new, since they know" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).once.returns(ts: "1", channel: "D1")
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    Slack::Client.expects(:update_message).with { |blocks:, **| blocks.sole.dig(:subtitle, :text) == "Stopped" }.once
    assert_nil Conversation::Watches.stop!(watch.reload, by: @alice)
  end

  test "a card is claimed before it is posted, so two workers never post it twice, and a post that failed is tried again" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert watch.claim_card!(Chat::Watch::PLACE_DIRECT)
    assert_not Chat::Watch.find(watch.id).claim_card!(Chat::Watch::PLACE_DIRECT)
    Slack::Client.expects(:post_message).never
    Slack::Client.expects(:update_message).never
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    watch.card_unclaimed!(Chat::Watch::PLACE_DIRECT)
    Slack::Client.unstub(:post_message)
    Slack::Client.expects(:post_message).raises(AdapterError, "channel_not_found")
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 is running.")
    assert_nil watch.reload.direct_card_claimed_at

    Slack::Client.unstub(:post_message)
    Slack::Client.expects(:post_message).once.returns(ts: "5", channel: "D1")
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 succeeded.")
    assert_equal "5", watch.reload.direct_card_message_id
  end

  test "a worker whose claim lapsed on a slow post and lost to another takes its own card back, so the place keeps one" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).once.with do |**|
      Chat::Watch.where(id: watch.id).update_all(direct_card_channel_id: "D1", direct_card_message_id: "1")
      true
    end.returns(ts: "2", channel: "D1")
    Slack::Client.expects(:delete_message).with { |channel:, ts:, **| [ channel, ts ] == [ "D1", "2" ] }.once

    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    assert_equal [ "D1", "1" ], watch.reload.card_in(Chat::Watch::PLACE_DIRECT)
  end

  test "a step that moved while the card was first posted is drawn on it at once, and a card that did not move is left alone" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Slack::Client.expects(:post_message).once.with do |**|
      Chat::Watch::Step.where(watch_id: watch.id).update_all(status: Chat::Watch::Step::STATUS_RUNNING)
      true
    end.returns(ts: "1", channel: "D1")
    Slack::Client.expects(:update_message).once.with { |ts:, blocks:, **| ts == "1" && blocks.sole.dig(:body, :text) == "Release run #46 is running." }

    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    other = @conversation.chat.watches.create!(workspace: @workspace, asker: @alice, title: "another", expires_at: 1.hour.from_now,
                                               limit_basis: Chat::Watch::BASIS_DEFAULT)
    Slack::Client.expects(:post_message).once.returns(ts: "2", channel: "D1")
    Slack::Client.expects(:update_message).never
    Conversation::Watches.tell!(other, Chat::Watch::Update::KIND_MILESTONE, "Another started.")
  end

  test "the verdict on a good end is drawn from what each step showed, and the card says it in a line" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    watch.update!(purpose: "ship main")
    Investigation.stubs(:unavailable_reason).returns(nil)
    watch.steps.sole.finished!(Chat::Watch::Step::STATUS_SUCCEEDED, reason: "Every instance of web runs 7676c83.")
    FirefightAi::WatchJudge.any_instance.expects(:standing)
                           .with { |happened:, offer:, evidence:, **| happened.start_with?("Done in") && !offer && evidence.join.include?("Every instance of web runs 7676c83.") }
                           .returns("web is serving 7676c83.")

    Conversation::Watches.conclude!(watch)

    watch.reload
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.status
    assert_match(/\ADone in .+ web is serving 7676c83\.\z/, watch.outcome)
    assert_match(/\ATook .+ web is serving 7676c83\.\z/, watch.end_reason)
    assert_equal watch.end_reason, Chat::Watch::Shown.why(watch)
  end

  test "a live update from a connection wakes the watches that read through it" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    row = @github.integration_environments.sole

    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ]) do
      Integrations::MapEvents.receive!(row, [ ResourceMap::Event.new(id: "e1", action: ResourceMap::Event::UPDATED, at: Time.current) ])
    end
  end

  test "a run's burst of events wakes a watch checked moments ago once, and the sweep catches the rest" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    row = @github.integration_environments.sole

    watch.update_columns(checked_at: 5.seconds.ago)
    assert_no_enqueued_jobs(only: WatchCheckJob) { Conversation::Watches.wake!(row, unless_checked_within: 15.seconds) }

    watch.update_columns(checked_at: 1.minute.ago)
    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ]) { Conversation::Watches.wake!(row, unless_checked_within: 15.seconds) }
  end

  test "Halon hears what its watches said once, at its next turn" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Conversation::Watches.tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "Release run #46 started.")

    assert_match "Watch \"release run #46\": Release run #46 started.", Conversation::Watches.untold_note(@conversation.chat)
    assert_nil Conversation::Watches.untold_note(@conversation.chat)
  end

  test "a workspace keeps only so many watches going at once" do
    answers("ci_runs" => History.result([], what: "repo"))
    Chat::Watch.stubs(:workspace_active).returns(stub(count: Chat::Watch::ACTIVE_LIMIT))

    assert_match "already has #{Chat::Watch::ACTIVE_LIMIT} watches going", Conversation::Watches.start(@turn, watch_of([ release_step ]))
  end

  test "a reading that is not a run is judged by the model over its recent readings, and asks no model while nothing changed" do
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying, updated 2 minutes ago" } ] })
    Conversation::Watches.start(@turn, watch_of([ { "label" => "web back", "capability" => "resource_status", "resource" => "web",
                                                     "done_when" => "live", "goal" => "web is live on the new version" } ], title: "web"))
    watch = @conversation.chat.watches.sole
    Investigation.stubs(:unavailable_reason).returns(nil)
    asked = []
    FirefightAi::WatchJudge.any_instance.expects(:reading).twice.with { |question:, readings:, **| asked << [ question, readings.map(&:last) ] }
                           .returns(FirefightAi::WatchJudge::Reading.new(state: "running", said: "Still deploying.", parts: []))
                           .then.returns(FirefightAi::WatchJudge::Reading.new(state: "done", said: "web is live.", parts: []))

    check!(watch)
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying, updated 3 minutes ago" } ] })
    check!(watch)
    assert_equal "Still deploying.", Chat::Watch::Shown.step_line(watch.steps.sole.reload), "the card's row says where it stands in a few words"
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is live" } ] })
    check!(watch)

    assert_equal "web is live on the new version It is done when the readings show live. Only a deploy of web that finished rolling out " \
                 "after #{watch.created_at.utc.strftime('%H:%M UTC')} counts as done. The first reading shows what was already live when the " \
                 "watch began, so it is not the new one.", asked.last.first, "Render's deploys are switched off here, so it cannot tell them apart"
    assert_equal [ "web is deploying, updated 2 minutes ago", "web is live" ], asked.last.last, "both readings that changed, oldest first"
    assert_equal "web back: done. web is live.", watch.updates.reload.first.text
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "with no model to judge, the words a reading step was given decide" do
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying" } ] })
    Conversation::Watches.start(@turn, watch_of([ { "label" => "web back", "capability" => "resource_status", "resource" => "web",
                                                     "done_when" => "live", "failed_when" => "crashed" } ], title: "web"))
    watch = @conversation.chat.watches.sole
    Investigation.stubs(:unavailable_reason).returns("unavailable")
    FirefightAi::WatchJudge.any_instance.expects(:reading).never

    check!(watch)
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web crashed on boot" } ] })
    check!(watch)
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status, "a failure is read once more before it ends the watch"
    check!(watch)

    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert_match "It reads: web crashed on boot", watch.outcome
  end

  test "a run held for someone to approve or start it is said once as waiting, a job of it or the run as a whole, rather than looking queued" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    answers("ci_runs" => History.result(finished_runs("Deploy", 7.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ { "label" => "Deploy", "capability" => "run_history", "resource" => "firefight", "name" => "Deploy", "run" => "41" } ]))
    watch = @conversation.chat.watches.sole
    started = Time.current
    built = History::Part.new(id: "1", name: "build", status: History::SUCCEEDED, started_at: started, finished_at: started + 30.seconds)
    held = History::Part.new(id: "2", name: "production", status: History::WAITING)
    answers("ci_runs" => History.result([ History::Run.new(id: "41", name: "Deploy", status: History::WAITING, started_at: started, parts: [ built, held ]) ], what: "repo"))

    2.times { check!(watch) }

    assert_equal [ "Deploy: build passed, production waiting for someone to approve or start it." ], watch.updates.reload.map(&:text)
    assert_equal "production waiting for someone to approve or start it, 1 of 2 done", Conversation::Watches.run_summary(
      History::Run.new(id: "41", status: History::WAITING, started_at: started, parts: [ built, held ])
    )
    assert_equal [ [ "deployment to production", Chat::Watch::Step::PART_HELD ] ],
                 Conversation::Watches.part_states(History::Run.new(id: "deployment-5", name: "deployment to production", status: History::WAITING, started_at: started))
    paused = History::Run.new(id: "7", name: "pipeline on main", status: History::WAITING, started_at: started, parts: [ built ])
    assert_equal [ [ "build", Chat::Watch::Step::PART_PASSED ], [ "pipeline on main", Chat::Watch::Step::PART_HELD ] ], Conversation::Watches.part_states(paused),
                 "a run held while none of its steps says so keeps its steps and is said held by its own name"
    assert_equal "pipeline on main waiting for someone to approve or start it, 1 of 1 done", Conversation::Watches.run_summary(paused)
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status
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
                           .with { |purpose:, happened:, offer:, **| purpose.include?("Northflank webhook") && happened.include?("trigger-northflank failed") && offer }
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
    assert_match "Started Watch", Conversation::Watches.start(@turn, watch_of([ step ], title: "the release workflow", purpose: "ship main"))
    watch = @conversation.chat.watches.sole
    assert_equal [ Chat::Watch::Step::READ_TOOL, "northflank_api_request" ], [ watch.steps.sole.capability, watch.steps.sole.tool_name ]
    check!(watch)
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status

    answers("api_request" => { "content" => [ { "type" => "text", "text" => '{"data":{"id":"90a3ba2f","status":"failure"}}' } ] })
    Investigation.stubs(:unavailable_reason).returns("unavailable")
    2.times { check!(watch) }

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
    ).then.returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::DONE, said: "The release run succeeded.",
                                           parts: passed.call("tag", "trigger-northflank", "build-images"))
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

  test "a run that never shows up in its history is handed back to Halon to repair, once, while a step before it still goes it waits" do
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

    assert_equal Chat::Watch::Step::STATUS_REPAIRING, deploy.reload.status
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status, "a step being repaired keeps the watch going"
    assert_includes watch.updates.reload.map(&:text), "I could not find a run of Web deploy in its history after 4 minutes. I am finding a better way to follow Web deploy."
    note = Conversation::Watches.hand_back_note(deploy)
    assert_match "It was started for: release main", note
    assert_match "call repair_watch with this watch and step", note
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

    assert_match "Started Watch", Conversation::Watches.start(@turn, watch_of([ step ], title: "primary"))
    check!(@conversation.chat.watches.find_by!(title: "primary"))
    replica = step.merge("arguments" => { "query" => "select 2", "use_replica" => true })
    assert_match "Started Watch", Conversation::Watches.start(@turn, watch_of([ replica ], title: "replica"))
    check!(@conversation.chat.watches.find_by!(title: "replica"))

    assert sent.any?
    assert(sent.all? { |arguments| arguments.key?("use_replica") })
    assert_equal [ false ], sent.select { |arguments| arguments["query"].include?("workspaces") }.map { |arguments| arguments["use_replica"] }.uniq
    assert_equal [ true ], sent.select { |arguments| arguments["query"] == "select 2" }.map { |arguments| arguments["use_replica"] }.uniq
  end

  test "Halon repairs a step in place with a better read, the same watch says what changed and follows the new read" do
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))
    Conversation::Watches.start(@turn, watch_of([ deploy_step ], title: "Deploy finished"))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole
    assert step.repair_asked!("I could not find a run of Web deploy in its history after 3 minutes.")
    northflank_api!
    answers("api_request" => northflank_run("running"))
    repair = Conversation::Tools::RepairWatch.new(@turn)

    said = repair.call(**{ "watch" => watch.id, "step" => "web deploy", "tool" => "northflank_api_request",
                           "arguments" => { "method" => "GET", "path" => "workflows/release/runs/release-v0-0-15" },
                           "goal" => "the release run finished", "why" => "Run history only lists builds, not workflow runs." })

    assert_match "Repaired Web deploy", said
    step.reload
    assert_equal [ Chat::Watch::Step::STATUS_WAITING, Chat::Watch::Step::READ_TOOL, "northflank_api_request", 1 ],
                 [ step.status, step.capability, step.tool_name, step.repairs ]
    assert_equal [ watch.id ], @conversation.chat.watches.pluck(:id), "the same watch, never a second one"
    assert_equal "Changed how I follow Web deploy: I now read northflank_api_request GET workflows/release/runs/release-v0-0-15 instead of " \
                 "Run history of web. Run history only lists builds, not workflow runs.",
                 watch.updates.find_by!(kind: Chat::Watch::Update::KIND_REPAIRED).text
    assert_match "has no step", repair.call(**{ "watch" => watch.id, "step" => "nope", "why" => "x" })
  end

  test "a first reading that shows nothing to follow is handed back to repair, and a step repaired too often is let go" do
    northflank_api!
    Investigation.stubs(:unavailable_reason).returns(nil)
    answers("api_request" => { "content" => [ { "type" => "text", "text" => '{"data":[]}' } ] })
    step = { "label" => "Release run", "tool" => "northflank_api_request", "goal" => "the release run finished",
             "arguments" => { "method" => "GET", "path" => "workflows/release/runs" } }
    Conversation::Watches.start(@turn, watch_of([ step ], title: "Release finished"))
    watch = @conversation.chat.watches.sole
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::NOTHING, said: "The list of runs is empty.", parts: [])
    )

    assert_enqueued_with(job: ConversationReplyJob) { check!(watch) }

    followed = watch.steps.sole
    assert_equal Chat::Watch::Step::STATUS_REPAIRING, followed.status
    assert_equal "The first reading of Release run showed nothing to follow. The list of runs is empty. I am finding a better way to follow Release run.",
                 watch.updates.sole.text
    assert_equal "Finding a better way to follow it. The first reading of Release run showed nothing to follow. The list of runs is empty.",
                 Chat::Watch::Shown.step_state(followed)

    followed.update_columns(repairs: Chat::Watch::Step::MAX_REPAIRS, status: Chat::Watch::Step::STATUS_WAITING, handed_back_at: nil, judged_at: nil)
    assert_no_enqueued_jobs(only: ConversationReplyJob) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_UNFOLLOWABLE, followed.reload.status
    assert_equal Chat::Watch::STATUS_STOPPED, watch.reload.status
  end

  test "a step left unrepaired for too long is no longer followed" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    watch.steps.sole.repair_asked!("Nothing showed.")

    travel Chat::Watch::Step::REPAIR_WITHIN + 1.minute do
      check!(watch)
    end

    assert_equal Chat::Watch::Step::STATUS_UNFOLLOWABLE, watch.steps.sole.status
    assert_includes watch.updates.reload.map(&:text), "I stopped following Release run #46. No better read was found for it within 15 minutes."
  end

  test "a watch keeps to its ceiling on reads, spacing its checks and waiting for the next hour once it is spent, said once" do
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "acme/firefight"))
    said = Conversation::Watches.start(@turn, watch_of([ release_step ], reads_per_hour: 6, minutes: 120))
    watch = @conversation.chat.watches.sole
    assert_match "It reads at most 6 times an hour", said
    assert_equal [ 6, 1 ], [ watch.reads_per_hour, watch.reads_total ]
    assert_in_delta 10.minutes.from_now, watch.next_check_at, 5.seconds
    assert_not Chat::Watch.due.exists?(id: watch.id), "the sweep leaves it until its next check"

    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))
    6.times { check!(watch) }

    assert_equal 6, watch.reload.reads_this_hour
    ceiling = watch.updates.where(kind: Chat::Watch::Update::KIND_CEILING)
    assert_equal 1, ceiling.count
    assert_match 'Watch "release run #46" made the 6 reads it allows itself an hour, so it reads again in', ceiling.sole.text
    assert_in_delta watch.hour_ends_at, watch.next_check_at, 1.second
    assert_equal "Reads at most 6 times an hour. 6 reads so far.", Chat::Watch::Shown.reads(watch)

    travel 61.minutes do
      check!(watch)
      watch.reload
      assert watch.reads_this_hour.positive?, "a new hour reads again"
      assert_equal 6 + watch.reads_this_hour, watch.reads_total
    end
  end

  test "the ceiling defaults to twice a read a minute for each step, within its bounds" do
    assert_equal 240, Chat::Watch.ceiling_for(nil, 2)
    assert_equal Chat::Watch::MOST_READS, Chat::Watch.ceiling_for(5000, 1)
    assert_equal Chat::Watch::FEWEST_READS, Chat::Watch.ceiling_for(1, 1)
  end

  test "a reading Halon takes in the chat with a watch's own read overrides what the watch had, and Halon is told they disagree" do
    northflank_api!
    Investigation.stubs(:unavailable_reason).returns(nil)
    arguments = { "method" => "GET", "path" => "workflows/release/runs/release-v0-0-15" }
    step = { "label" => "Release run", "tool" => "northflank_api_request", "arguments" => arguments, "goal" => "the release run finished" }
    answers("api_request" => northflank_run("queued"))
    Conversation::Watches.start(@turn, watch_of([ step ], title: "Release finished"))
    watch = @conversation.chat.watches.sole
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::NOT_STARTED, said: "Queued.", parts: [])
    )
    check!(watch)
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::FAILED, said: "The run failed at build-images.", parts: [],
                                           link: "https://app.northflank.com/t/acme/project/p/workflows/release/runs/release-v0-0-15")
    )

    assert_nil Conversation::Watches.observe!(@conversation.chat, "northflank_api_request", arguments.merge("path" => "workflows/other"), "anything")
    Integrations::NativeExecutor.expects(:call).never
    failed = northflank_run("failure")["content"].first["text"]
    assert_nil Conversation::Watches.observe!(@conversation.chat, "northflank_api_request", arguments, failed), "a failure is read once more first"
    note = Conversation::Watches.observe!(@conversation.chat, "northflank_api_request", arguments.merge("intent" => "Check the run"), failed)

    assert_match 'Watch "Release finished" had Release run as: Waiting for it to start.', note
    assert_match "The fresh reading wins", note
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    corrected = watch.updates.find_by!(kind: Chat::Watch::Update::KIND_CORRECTED)
    assert_equal 'A fresh reading in the chat shows Release run failed, where the watch "Release finished" still had it not started. It now goes by the fresh reading.',
                 corrected.text
    assert corrected.told_at, "Halon already heard it, so its next turn does not hear it again"
    assert_equal "https://app.northflank.com/t/acme/project/p/workflows/release/runs/release-v0-0-15", watch.steps.sole.run_url
  end

  test "a judge's link is kept only when the reading holds it word for word" do
    judge = FirefightAi::WatchJudge.new(@workspace)
    judge.stubs(:ask).returns({ state: "running", said: "Running.", parts: [], link: "https://made.up/run" }.with_indifferent_access)
    assert_nil judge.reading(question: "done", readings: [ [ Time.current, "status running" ] ], so_far: "not started").link

    judge.stubs(:ask).returns({ state: "running", said: "Running.", parts: [], link: "https://ci.test/runs/1" }.with_indifferent_access)
    assert_equal "https://ci.test/runs/1",
                 judge.reading(question: "done", readings: [ [ 1.minute.ago, "run https://ci.test/runs/1 queued" ], [ Time.current, "running" ] ], so_far: "not started").link
  end

  test "a reading that stays the same is judged again every few minutes, with how long it has stayed so" do
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web error rate 0.2%" } ] })
    Conversation::Watches.start(@turn, watch_of([ { "label" => "web steady", "capability" => "resource_status", "resource" => "web",
                                                     "goal" => "the error rate stays under 1% for ten minutes" } ], title: "Web steady"))
    watch = @conversation.chat.watches.sole
    Investigation.stubs(:unavailable_reason).returns(nil)
    told = []
    FirefightAi::WatchJudge.any_instance.stubs(:reading).with { |steady: nil, **| told << steady }
                           .returns(FirefightAi::WatchJudge::Reading.new(state: "running", said: "Under 1%.", parts: []))

    check!(watch)
    travel(2.minutes) { check!(watch) }
    travel(6.minutes) { check!(watch) }

    assert_equal 2, told.size, "an unchanged reading is not judged again within five minutes"
    assert_nil told.first
    assert_equal "The reading has stayed the same for 6 minutes.", told.last
  end

  test "list_watches reads each watch that still goes again first, so it answers from a fresh reading" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    Chat::Watch.where(id: watch.id).update_all(checked_at: Time.current, next_check_at: 10.minutes.from_now)
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))

    listed = JSON.parse(Conversation::Tools::ListWatches.new(@turn).call)

    assert_equal "running", listed.sole["steps"].sole["status"]
    assert listed.sole["steps"].sole["last_read"]
    assert_equal 'Watch "release run #46"', listed.sole["name"]
  end

  test "a read step following a Northflank workflow run through the general read keeps its connection, wakes on a live update, learns its usual time and finishes" do
    northflank_api!
    Investigation.stubs(:unavailable_reason).returns(nil)
    environment = @workspace.integrations.find_by!(provider: "northflank").integration_environments.sole
    arguments = { "method" => "GET", "path" => "workflows/release/runs/release-v0-0-16" }
    earlier = Chat::Watch.create!(chat: @conversation.chat_record, workspace: @workspace, asker: @alice, title: "Earlier release", expires_at: 1.hour.from_now,
                                  limit_basis: Chat::Watch::BASIS_DEFAULT, status: Chat::Watch::STATUS_SUCCEEDED)
    earlier.steps.create!(position: 0, label: "Release run", capability: Chat::Watch::Step::READ_TOOL, tool_name: "northflank_api_request",
                          arguments: arguments.merge("path" => "workflows/release/runs/release-v0-0-15"), status: Chat::Watch::Step::STATUS_SUCCEEDED,
                          read_signature: Chat::Watch::Step.signature("northflank_api_request", arguments), started_at: 2.days.ago, finished_at: 2.days.ago + 7.minutes)
    answers("api_request" => northflank_run("queued"))

    said = Conversation::Watches.start(@turn, watch_of([ { "label" => "Release run", "tool" => "northflank_api_request", "arguments" => arguments,
                                                           "goal" => "the release workflow run finished" } ], title: "Release"))

    assert_match "This usually takes about 7 minutes", said
    watch = @conversation.chat.watches.find_by!(title: "Release")
    step = watch.steps.sole
    assert_equal [ environment.id, 7.minutes.to_i ], [ step.integration_environment_id, step.usual_seconds ]
    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ]) { Conversation::Watches.wake!(environment) }

    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::RUNNING, said: "build-images running, 4 of 7 jobs done.", parts: [])
    )
    answers("api_request" => northflank_run("running", jobs: 4))
    check!(watch)
    assert_equal "build-images running, 4 of 7 jobs done.", Chat::Watch::Shown.step_line(step.reload)

    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: FirefightAi::Schemas::WatchReading::DONE, said: "The release run succeeded.", parts: [])
    )
    FirefightAi::WatchJudge.any_instance.stubs(:standing).returns("unknown")
    answers("api_request" => northflank_run("success", jobs: 7))
    check!(watch)

    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal 2, step.readings.size, "each reading that changed is kept for the judge"
  end

  test "a step can name the part of a long answer to watch, and without one a long answer keeps its end, where a later failure shows" do
    nodes = Array.new(400) { |index| { "name" => "node-#{index}", "status" => "success" } } + [ { "name" => "deploy-web", "status" => "failed" } ]
    text = "Northflank answered GET workflows/release/runs/7.\n#{{ 'data' => { 'status' => 'running', 'nodes' => nodes } }.to_json}\nOpen in Northflank: https://app.northflank.com/x"

    assert_equal "data.status: running", Chat::Watch::Step.focused(text, "data.status")
    assert_includes Chat::Watch::Step.focused(text, "data.nodes.status"), "failed"
    whole = Chat::Watch::Step.focused(text, nil)
    assert_operator whole.length, :<=, Chat::Watch::Step::READING_LIMIT + 200
    assert_includes whole, "deploy-web"
    assert_includes whole, "\"status\":\"running\""
    assert_nil Chat::Watch::Step.at_path(text, "data.missing")

    northflank_api!
    answers("api_request" => { "content" => [ { "type" => "text", "text" => text } ] })
    refused = Conversation::Watches.start(@turn, watch_of([ { "label" => "Release run", "tool" => "northflank_api_request", "focus" => "data.state",
                                                              "arguments" => { "method" => "GET", "path" => "workflows/release/runs/7" }, "goal" => "it finished" } ]))
    assert_match "its first reading holds nothing at data.state", refused
  end

  test "a run history name that matches nothing says at once which runs the history holds" do
    answers("deploy_history" => History.result(finished_runs("build", 4.minutes) + finished_runs("deploy", 2.minutes), what: "web"))
    Integrations::NativeExecutor.stubs(:call).with { |tool:, arguments:, **| tool.name == "deploy_history" && arguments["name"] == "release" }
                                .returns(History.result([], what: "web"))

    said = Conversation::Watches.start(@turn, watch_of([ { "label" => "Web release", "capability" => "run_history", "resource" => "web", "name" => "release" } ]))

    assert_match "Nothing was started", said
    assert_match 'Its run history holds runs named "deploy" and "build", none named "release", so it cannot follow that.', said
    assert_not Chat::Watch.exists?(workspace_id: @workspace.id, title: "release run #46")
  end

  test "a repair to the very read a step already makes is refused, and one that changes an argument names what changed" do
    northflank_api!
    arguments = { "method" => "GET", "path" => "workflows/release/runs" }
    answers("api_request" => northflank_run("queued"))
    Conversation::Watches.start(@turn, watch_of([ { "label" => "Release run", "tool" => "northflank_api_request", "arguments" => arguments,
                                                    "goal" => "the release run finished" } ], title: "Release"))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole
    repair = Conversation::Tools::RepairWatch.new(@turn)

    same = repair.call(**{ "watch" => watch.id, "step" => "Release run", "tool" => "northflank_api_request", "arguments" => arguments.merge("intent" => "again"),
                           "why" => "Try again." })
    assert_match "Not repaired. That is the read Release run already makes", same
    assert_match "Find a different read", same
    assert_equal 0, step.reload.repairs

    changed = repair.call(**{ "watch" => watch.id, "step" => "Release run", "tool" => "northflank_api_request",
                              "arguments" => arguments.merge("path" => "workflows/release/runs/release-v0-0-16"), "why" => "The list holds older runs." })
    assert_match "Repaired Release run", changed
    assert_equal "Changed how I follow Release run: I still read with northflank_api_request, now with path workflows/release/runs/release-v0-0-16 " \
                 "instead of workflows/release/runs. The list holds older runs.", watch.updates.find_by!(kind: Chat::Watch::Update::KIND_REPAIRED).text
  end

  test "a step naming a capability as its tool is that capability, with its own statuses" do
    answers("ci_runs" => History.result(finished_runs("release", 9.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ { "label" => "Release run", "tool" => "run_history",
                                                    "arguments" => { "resource" => "firefight", "name" => "release" } } ]))

    step = @conversation.chat.watches.sole.steps.sole
    assert_equal [ Integrations::Capabilities::HISTORY, "release", 9.minutes.to_i ], [ step.capability, step.run_name, step.usual_seconds ]
  end

  test "with a watch of theirs going, start_watch starts nothing until Halon says whether the steps join it or are separate" do
    start_release_watch
    release = @conversation.chat.watches.sole
    tool = Conversation::Tools::StartWatch.new(@turn)
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))

    asked = tool.call(**watch_of([ deploy_step ], title: "Web deploy finished", purpose: "ship the release").symbolize_keys)

    assert_match "Nothing was started yet", asked
    assert_match %(- Watch "release run #46" (watch #{release.id}). Steps: Release run #46.), asked
    assert_match "call start_watch again with add_to and its id", asked
    assert_match "separate true", asked
    assert_equal 1, @conversation.chat.watches.count

    separate = tool.call(**watch_of([ deploy_step ], title: "Database backup", separate: true).symbolize_keys)

    assert_match 'Started Watch "Database backup"', separate
    assert_match Conversation::Watches::STRIP_NOTE, separate, "a dashboard chat is pointed to the strip"
    assert_equal 2, @conversation.chat.watches.active.count
  end

  test "a runbook's watch and a watch someone else started in the chat never ask, and a chat in Slack is never pointed to the strip" do
    thread = Conversation.create!(workspace: @workspace, kind: Conversation::KIND_CHANNEL, channel_id: "C0WATCH", thread_id: "1700000000.000100",
                                  started_by: @alice, max_turns: 5, max_spend_cents: 100)
    @turn = Conversation::Turn.new(thread, asker: @alice)
    start_release_watch
    bob = workspace_memberships(:bob_workspace_one)
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))

    said = Conversation::Tools::StartWatch.new(Conversation::Turn.new(thread, asker: bob)).call(**watch_of([ deploy_step ], title: "Web deploy").symbolize_keys)

    assert_match 'Started Watch "Web deploy"', said
    assert_no_match "Watching strip", said
    assert_match 'Started Watch "runbook"', Conversation::Watches.start(@turn, watch_of([ deploy_step ], title: "runbook"))
  end

  test "steps on the same subject join the watch already going, its limit moving to leave them time, said wherever it reports" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("deploy_history" => History.result(finished_runs("deploy", 20.minutes), what: "web"))
    Slack::Client.expects(:post_message).with { |channel:, **| channel == @alice.platform_user_id }.once.returns(ts: "1", channel: "D1")

    said = travel(30.minutes) do
      Conversation::Tools::StartWatch.new(@turn).call(**watch_of([ deploy_step ], title: "Release deployed", add_to: watch.id).symbolize_keys)
    end

    assert_match %(Added Web deploy to Watch "Release deployed" (watch #{watch.id}) rather than starting another watch.), said
    assert_match "It now watches for up to 1 hr 10 min from when it started, to leave them time to finish. They usually take about 20 minutes.", said
    assert_match "It reads at most 240 times an hour", said
    assert_match Conversation::Watches::STRIP_NOTE, said
    watch.reload
    assert_equal 1, @conversation.chat.watches.count
    assert_equal [ "Release run #46", "Web deploy" ], watch.steps.map(&:label)
    assert_equal [ 0, 1 ], watch.steps.map(&:position)
    assert_nil watch.steps.first.added_at
    assert_not_nil watch.steps.second.added_at
    assert_equal [ "Release deployed", Chat::Watch::BASIS_ADDED, 240 ], [ watch.title, watch.limit_basis, watch.reads_per_hour ]
    assert_in_delta watch.created_at + 70.minutes, watch.expires_at, 5.seconds
    added = watch.updates.sole
    assert_equal [ Chat::Watch::Update::KIND_STEPS_ADDED, "Now also following Web deploy. It now watches for up to 1 hr 10 min from when it started." ],
                 [ added.kind, added.text ]
    assert_not_nil added.told_at, "Halon says it in its own answer, so it is not heard again"
    assert_equal "Up to 1 hr 10 min. Moved later when steps were added, to leave them time to finish.", Chat::Watch::Shown.basis(watch)
    assert_enqueued_with(job: WatchCheckJob, args: [ watch.id ])
  end

  test "a limit that already leaves the added steps time stays as it was" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    expires = watch.expires_at
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))

    said = Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id))

    assert_match "Its limit of 40 min from when it started already leaves them time. They usually take about 4 minutes.", said
    assert_equal [ expires, Chat::Watch::BASIS_HISTORY, "release run #46" ], [ watch.reload.expires_at, watch.limit_basis, watch.title ]
    assert_equal "Now also following Web deploy.", watch.updates.sole.text
  end

  test "a limit the person asked for stays theirs when steps join, and Halon is told they may not finish within it" do
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ release_step ], minutes: 30))
    watch = @conversation.chat.watches.sole
    expires = watch.expires_at
    answers("deploy_history" => History.result(finished_runs("deploy", 20.minutes), what: "web"))

    said = travel(20.minutes) { Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id)) }

    assert_match "It keeps the limit of 30 min from when it started that the person asked for, and the added steps may not finish within it. " \
                 "They usually take about 20 minutes. Tell them so, and offer more time", said
    assert_equal [ expires, Chat::Watch::BASIS_ASKED ], [ watch.reload.expires_at, watch.limit_basis ]
    assert_equal "Now also following Web deploy.", watch.updates.sole.text

    travel(21.minutes) { Conversation::Watches.start(@turn, watch_of([ deploy_step.merge("label" => "Health") ], add_to: watch.id, minutes: 60)) }
    assert_in_delta watch.created_at + 81.minutes, watch.reload.expires_at, 5.seconds, "minutes the person gives with the steps move it"
  end

  test "a ceiling Halon set from a provider's limit is kept when steps join, and a number given with them wins" do
    answers("ci_runs" => History.result(finished_runs("release", 18.minutes), what: "repo"))
    Conversation::Watches.start(@turn, watch_of([ release_step ], reads_per_hour: 30))
    watch = @conversation.chat.watches.sole
    assert watch.reads_per_hour_asked?
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))

    Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id))
    assert_equal 30, watch.reload.reads_per_hour

    Conversation::Watches.start(@turn, watch_of([ deploy_step.merge("label" => "Web deploy again") ], add_to: watch.id, reads_per_hour: 60))
    assert_equal 60, watch.reload.reads_per_hour
  end

  test "only whoever started a watch adds to it, while it goes and within its steps" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    bob = workspace_memberships(:bob_workspace_one)
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))

    assert_match "No watch nope in this chat.", Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: "nope"))
    assert_equal %(Only #{@alice.display_name} can add steps to the watch "release run #46", since it reads as them. Start a separate watch.),
                 watch.add_blocked_reason(bob, 1)
    assert_match "already follows 1 step, and a watch follows at most #{Chat::Watch::MAX_STEPS} at once",
                 Conversation::Watches.start(@turn, watch_of(Array.new(Chat::Watch::MAX_STEPS) { deploy_step }, add_to: watch.id))

    watch.finish!(Chat::Watch::STATUS_STOPPED, outcome: "Stopped.")
    assert_equal %(Watch "release run #46" has already ended, so start a new watch for these steps.),
                 Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id))
    assert_equal 1, watch.steps.count
  end

  test "a check that read the steps before more joined never ends the watch as done or out of time" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    read_before = watch.steps_added_at
    watch.add_steps!([ { label: "Web deploy", capability: Integrations::Capabilities::HISTORY, arguments: {} } ],
                     until_at: 2.hours.from_now, reads_per_hour: 240)

    assert_not watch.finish!(Chat::Watch::STATUS_SUCCEEDED, outcome: "Done.", steps_added_at: read_before)
    assert_not watch.finish!(Chat::Watch::STATUS_TIMED_OUT, outcome: "Out of time.", expired_by: 1.hour.from_now)
    assert watch.reload.active?
    assert watch.finish!(Chat::Watch::STATUS_SUCCEEDED, outcome: "Done.", steps_added_at: watch.steps_added_at)
  end

  test "a step added later follows the first run that started around when it was added, and waits from then" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))
    travel(30.minutes) { Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id)) }
    step = watch.reload.steps.second

    earlier = run_of("1", History::RUNNING, watch.created_at, name: "deploy")
    later = run_of("2", History::RUNNING, step.added_at - 1.minute, name: "deploy")

    assert_equal later, step.run_among([ earlier, later ])
    assert_equal step.added_at, step.waiting_since([])
  end

  test "the strip says where a watch going stands in a line" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    assert_equal "Release run #46: not started", Chat::Watch::Shown.standing(watch)

    answers("deploy_history" => History.result(finished_runs("deploy", 4.minutes), what: "web"))
    Conversation::Watches.start(@turn, watch_of([ deploy_step ], add_to: watch.id))
    watch.reload.steps.first.finished!(Chat::Watch::Step::STATUS_SUCCEEDED)
    watch.steps.second.update!(status: Chat::Watch::Step::STATUS_RUNNING, summary: "build-images running, 2 of 3 done")

    assert_equal "1 of 2 done. Web deploy: build-images running, 2 of 3 done", Chat::Watch::Shown.standing(watch.reload)
  end

  test "a check reads the person's reach and the workspace's tools once, however many steps it reads" do
    answers("ci_runs" => History.result([ run_of("46", History::RUNNING, Time.current) ], what: "repo"))
    few_watch = watch_with_steps(2)
    check!(few_watch)
    few = queries_sent { check!(few_watch) }
    many_watch = watch_with_steps(Chat::Watch::MAX_STEPS)
    check!(many_watch)
    many = queries_sent { check!(many_watch) }

    reach = ->(sent) { sent.grep(/FROM "ability_grants"|AS t0_r0 .*FROM "integration_tools" .*WHERE "integration_tools"."enabled"(?!.*"integration_tools"."integration_id" =)/) }
    assert_equal reach.call(few).size, reach.call(many).size, repeated_queries(reach.call(many))
    assert_equal Chat::Watch::MAX_STEPS, many_watch.steps.count
  end

  private

  # A watch of release runs, each a step of its own, started without asking the provider how long they take.
  def watch_with_steps(count)
    steps = Array.new(count) { |index| release_step.merge("label" => "Release run ##{index}", "run" => index.to_s) }
    said = Conversation::Watches.start(@turn, watch_of(steps, title: "release #{SecureRandom.hex(2)}", minutes: 60))
    @conversation.chat.watches.find(said[/\(watch (\h{8}-[\h-]+)\)/, 1])
  end

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

  # The buttons on a message, in an actions block or a card, by action id or by address for a link.
  def actions_of(blocks)
    blocks.flat_map { |block| block[:type] == "actions" ? block[:elements] : block[:actions].to_a }.map { |button| button[:action_id] || button[:url] }
  end

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
