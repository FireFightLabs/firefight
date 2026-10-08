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

  test "stopping says so once, and only whoever asked may" do
    start_release_watch
    watch = @conversation.chat.watches.sole

    assert_equal "Only #{@alice.display_name} can stop this watch.", Conversation::Watches.stop!(watch, by: workspace_memberships(:bob_workspace_one))
    assert_nil Conversation::Watches.stop!(watch, by: @alice)
    assert_equal Chat::Watch::NOTHING_TO_STOP, Conversation::Watches.stop!(watch, by: @alice)

    assert_equal [ Chat::Watch::STATUS_STOPPED, @alice ], [ watch.reload.status, watch.stopped_by ]
    assert_equal [ "#{@alice.display_name} stopped the watch on release run #46." ], watch.updates.map(&:text)
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

  test "more time is given up to a day from when it started, and only while it goes" do
    start_release_watch
    watch = @conversation.chat.watches.sole
    extend_watch = Conversation::Tools::ExtendWatch.new(@turn)

    assert_match "now watched for up to 1 hr 30 min", extend_watch.call(watch: watch.id, minutes: 90)
    assert_equal [ watch.created_at + 90.minutes, Chat::Watch::BASIS_ASKED ], [ watch.reload.expires_at, watch.limit_basis ]
    extend_watch.call(watch: watch.id, minutes: 5000)
    assert_equal watch.created_at + 24.hours, watch.reload.expires_at

    Conversation::Watches.stop!(watch, by: @alice)
    assert_equal Chat::Watch::NOTHING_TO_STOP, extend_watch.call(watch: watch.id, minutes: 120)
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
    Slack::Client.expects(:post_message).with { |channel:, blocks:, **| channel == @alice.platform_user_id && blocks.none? { |block| block[:type] == "actions" } }
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
    FirefightAi::WatchJudge.any_instance.expects(:reading).once.returns(FirefightAi::WatchJudge::Reading.new(state: "going", said: "Still deploying."))

    check!(watch)
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is deploying, updated 3 minutes ago" } ] })
    check!(watch)
    answers("describe_resource" => { "content" => [ { "type" => "text", "text" => "web is live" } ] })
    check!(watch)

    assert_equal "web back: done.", watch.updates.reload.first.text
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
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

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
