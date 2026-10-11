require "test_helper"

# A step waiting for a deploy keeps the deploy live when the watch began and counts only a newer one that finished
# rolling out and is serving, or the commit, tag or branch named. The provider's deploys are stubbed as any provider
# answers them through the shared contract.
class Conversation::Watches::NewDeployTest < ActiveSupport::TestCase
  include SlackClientStubHelper
  include ActiveJob::TestHelper

  History = Integrations::Capabilities::History
  Deploys = Integrations::Capabilities::Deploys
  Reading = FirefightAi::WatchJudge::Reading
  OLD = "cf0bcbe400e34759df35b4011771aa8c776ca049".freeze
  NEW = "f23b4dc3fe04aa11bb22cc33dd44ee55ff667788".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @render = connect!("render", "Render", %w[list_deployments describe_resource])
    @service = place!(@render, ResourceMap::KIND_SERVICE, "web", "srv-web")
    @began = Time.current.change(usec: 0)
    @old = Deploys::Deploy.new(id: "dep-old", commit: OLD, branch: "main", status: History::SUCCEEDED, live: true,
                               started_at: @began - 6.hours, finished_at: @began - 6.hours + 4.seconds)
    stub_post_message
    status("Rollout: COMPLETED.")
    Investigation.stubs(:unavailable_reason).returns(nil)
    # The model is sure it is done on every reading, as it was on the old rollout's.
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(Reading.new(state: "done", said: "web's latest rollout is completed and serving.", parts: []))
  end

  test "the old rollout already complete never ends the step, and a new rollout of another commit does once it is live" do
    deploys([ @old ])
    status("Rollout: COMPLETED, DEPLOYING, since #{@old.finished_at.iso8601}. Deployed commit #{OLD}")
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    assert_equal "dep-old", step.deploy_baseline.id
    assert_equal "Waiting for a new deploy of web to start (live now: cf0bcbe since #{clock(@old.finished_at)}).", Chat::Watch::Shown.step_line(step)

    check!(watch)
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status, "the deploy live when it began is not the new one"
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status

    rolling = Deploys::Deploy.new(id: "dep-new", commit: NEW, branch: "main", status: History::RUNNING, live: true, started_at: @began + 4.minutes)
    deploys([ rolling, @old.with(live: false) ])
    status("Rollout: IN_PROGRESS, DEPLOYING. Deployed commit #{NEW}")
    travel(5.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_RUNNING, step.reload.status, "done is held while the new deploy rolls out"
    assert_equal "A new deploy of web is rolling out (f23b4dc, started #{clock(@began + 4.minutes)}).", step.summary

    deploys([ rolling.with(status: History::SUCCEEDED, finished_at: @began + 9.minutes), @old.with(live: false) ])
    status("Rollout: COMPLETED, DEPLOYING. Deployed commit #{NEW}")
    travel(10.minutes) { check!(watch) }

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "a named commit waits for that commit, past a newer deploy of another" do
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "commit" => NEW.first(7) }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole
    assert_equal "Waiting for f23b4dc to deploy to web (live now: cf0bcbe since #{clock(@old.finished_at)}).", step.summary

    other = Deploys::Deploy.new(id: "dep-other", commit: "abcdef0123456789", status: History::SUCCEEDED, live: true, started_at: @began + 1.minute,
                                finished_at: @began + 2.minutes)
    deploys([ other, @old.with(live: false) ])
    travel(3.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status

    named = Deploys::Deploy.new(id: "dep-named", commit: NEW, status: History::SUCCEEDED, live: true, started_at: @began + 4.minutes, finished_at: @began + 6.minutes)
    deploys([ named, other.with(live: false), @old.with(live: false) ])
    travel(7.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
  end

  test "a commit already live when the watch began counts at once" do
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "commit" => OLD }))
    watch = @conversation.chat.watches.sole

    check!(watch)

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, watch.steps.sole.reload.status
  end

  test "a named tag is read as its commit through the code host, once the release pushed it" do
    github = connect!("github", "GitHub", %w[commit_lookup])
    repository = place!(github, ResourceMap::KIND_REPOSITORY, "firefight", "acme/firefight")
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @service, to_resource: repository, relation: ResourceMap::RELATION_BUILT_FROM,
                              origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "tag" => "v1.4.0" }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    lookup(nil)
    check!(watch)
    assert_nil step.reload.new_deploy[Chat::Watch::Step::NewDeploy::TAG_COMMIT], "a tag not pushed yet is asked again"

    lookup(NEW)
    named = Deploys::Deploy.new(id: "dep-new", commit: NEW, status: History::SUCCEEDED, live: true, started_at: @began + 4.minutes, finished_at: @began + 6.minutes)
    deploys([ named, @old.with(live: false) ])
    travel(7.minutes) { check!(watch) }

    assert_equal NEW, step.reload.new_deploy[Chat::Watch::Step::NewDeploy::TAG_COMMIT]
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.status
    assert Ability::Invocation.where(workspace: @workspace, action_key: "github.commit_lookup").exists?, "read as the asker, in Activity"
  end

  test "a named branch counts only a newer deploy from that branch" do
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "branch" => "release" }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    from_main = Deploys::Deploy.new(id: "dep-main", commit: NEW, branch: "main", status: History::SUCCEEDED, live: true, started_at: @began + 1.minute)
    deploys([ from_main, @old.with(live: false) ])
    travel(2.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status
    assert_equal "Waiting for a new deploy of web from release to start (live now: cf0bcbe since #{clock(@old.finished_at)}).", step.summary

    from_release = Deploys::Deploy.new(id: "dep-release", commit: "1234567abcdef", branch: "release", status: History::SUCCEEDED, live: true,
                                       started_at: @began + 3.minutes, finished_at: @began + 5.minutes)
    deploys([ from_release, from_main.with(live: false), @old.with(live: false) ])
    travel(6.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
  end

  test "with nothing named, a new deploy that failed ends the step failed" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole

    deploys([ Deploys::Deploy.new(id: "dep-new", commit: NEW, status: History::FAILED, started_at: @began + 1.minute, finished_at: @began + 3.minutes), @old ])
    travel(4.minutes) { check!(watch) }

    assert_equal [ Chat::Watch::Step::STATUS_FAILED, "The new deploy of web failed (f23b4dc)." ], [ watch.steps.sole.reload.status, watch.steps.sole.reason ]
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
  end

  test "the baseline is kept on the step, so a restart and a repair to the same resource keep it" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    kept = watch.steps.sole.new_deploy

    # A new deploy went live while no worker ran. A fresh process reads the baseline back from the database.
    later = Deploys::Deploy.new(id: "dep-later", commit: "9999999aaaaaaa", status: History::SUCCEEDED, live: true, started_at: @began + 2.minutes)
    deploys([ later, @old.with(live: false) ])
    Conversation::Watches.repair!(watch.reload, watch.steps.sole, { "capability" => "recent_deploys", "resource" => "web" }, why: "Status only says now.")
    step = watch.steps.sole.reload
    assert_equal kept[Chat::Watch::Step::NewDeploy::BASELINE], step.new_deploy[Chat::Watch::Step::NewDeploy::BASELINE]
    assert_equal kept[Chat::Watch::Step::NewDeploy::SINCE], step.new_deploy[Chat::Watch::Step::NewDeploy::SINCE]

    travel(3.minutes) { check!(Chat::Watch.find(watch.id)) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status, "the deploy that went out after the watch began counts"
  end

  test "a step added to a watch later takes its baseline when it begins, not when the watch began" do
    deploys([ @old ])
    start([ { "label" => "web healthy", "capability" => "resource_status", "resource" => "web", "goal" => "web answers its health check" } ])
    watch = @conversation.chat.watches.sole
    middle = Deploys::Deploy.new(id: "dep-middle", commit: "7777777abcdef", status: History::SUCCEEDED, live: true, started_at: @began + 5.minutes,
                                 finished_at: @began + 6.minutes)
    deploys([ middle, @old.with(live: false) ])

    said = travel(10.minutes) { Conversation::Watches.start(@turn, { "title" => "Release", "steps" => rollout_step, "add_to" => watch.id }) }
    added = watch.steps.reload.find_by!(label: "Production web rollout")

    assert_equal "dep-middle", added.deploy_baseline.id, "the deploy that went out before it was added is not the new one"
    assert_in_delta @began + 10.minutes, added.deploy_since, 2.seconds
    assert_match "Production web rollout: Waiting for a new deploy of web to start (live now: 7777777", said
    travel(11.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_WAITING, added.reload.status
  end

  test "a repair that follows another resource starts from the deploy live on that one now" do
    api = place!(@render, ResourceMap::KIND_SERVICE, "api", "srv-api")
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    on_api = Deploys::Deploy.new(id: "dep-api", commit: NEW, status: History::SUCCEEDED, live: true, started_at: @began - 1.hour)
    Integrations::NativeExecutor.stubs(:call).with { |tool:, arguments:, **| tool.name == "list_deployments" && arguments.value?(api.external_id) }
                                .returns(Deploys.with_deploys(text("api deploys"), [ on_api ]))

    Conversation::Watches.repair!(watch, watch.steps.sole, { "capability" => "resource_status", "resource" => "api" }, why: "It was the wrong service.")

    assert_equal "dep-api", watch.steps.sole.reload.deploy_baseline.id
  end

  test "a provider that cannot tell deploys apart counts a deploy finished after the watch began, and says so" do
    Integrations::NativeExecutor.stubs(:call).returns(text("Deploys of web: one went out this morning."))
    status("Rollout: COMPLETED. Running the latest version.")
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    assert_not step.deploy_identity?
    assert_equal "Waiting for a new deploy of web. Render does not say which deploy is live, so one that finishes after #{clock(@began)} counts.", step.summary
    asked = []
    FirefightAi::WatchJudge.any_instance.stubs(:reading).with { |question:, **| asked << question }
                           .returns(Reading.new(state: "done", said: "Completed.", parts: []))

    check!(watch)
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status, "the reading the watch began with is the old deploy"
    assert_match "Only a deploy of web that finished rolling out after #{clock(@began)} counts as done.", asked.last

    status("Rollout: COMPLETED. Running build 812 of commit #{NEW}.")
    travel(6.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
  end

  test "a step that waits for no deploy is read as before" do
    deploys([ @old ])
    start([ { "label" => "web healthy", "capability" => "resource_status", "resource" => "web", "goal" => "web answers its health check" } ])
    watch = @conversation.chat.watches.sole
    status("Health: passing")

    check!(watch)

    assert_nil watch.steps.sole.new_deploy
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  private

  def rollout_step(extra = {})
    [ { "label" => "Production web rollout", "capability" => "resource_status", "resource" => "web", "connection" => "render",
        "goal" => "The latest production web rollout is completed and serving" }.merge(extra) ]
  end

  def start(steps) = Conversation::Watches.start(@turn, { "title" => "Firefight production release", "steps" => steps })

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

  def text(words) = { "content" => [ { "type" => "text", "text" => words } ] }

  def deploys(listed)
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == "list_deployments" }
                                .returns(Deploys.with_deploys(text("Deploys of web."), listed))
  end

  def status(words) = Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == "describe_resource" }.returns(text(words))

  def lookup(commit)
    answer = commit ? text("Commit #{commit}\nAuthor: Alice") : text("No commit v1.4.0 in acme/firefight.").merge("isError" => true)
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool.name == "commit_lookup" }.returns(answer)
  end

  def clock(time) = time.utc.strftime("%H:%M UTC")

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil, next_check_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
