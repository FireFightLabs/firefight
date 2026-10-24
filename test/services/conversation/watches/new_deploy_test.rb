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
    stub_update_message
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

  test "a commit already live when the watch starts ends it at once as succeeded, saying so by the resource's name, without asking the model" do
    FirefightAi::WatchJudge.any_instance.unstub(:reading)
    FirefightAi::WatchJudge.any_instance.expects(:reading).never
    deploys([ @old ])
    start(rollout_step("resource" => @service.id, "new_deploy" => { "commit" => OLD }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole
    assert_equal "cf0bcbe is already live on web.", step.summary

    check!(watch)

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal "cf0bcbe is already live on web.", step.reason
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert_match "cf0bcbe is already live on web.", watch.outcome
  end

  test "a resource the person who asked cannot see on the map is never named, only kept as they gave it" do
    deploys([ @old ])
    start(rollout_step("resource" => @service.id, "new_deploy" => { "commit" => NEW }))
    step = @conversation.chat.watches.sole.steps.sole
    ResourceMap::Resource.stubs(:visible_to).with(@alice, @workspace).returns(ResourceMap::Resource.none)

    assert_equal @service.id, step.reload.deploy_resource_words
  end

  test "a named commit that goes live at a later read ends the step at once, whatever the reading says" do
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(Reading.new(state: "running", said: "Still rolling.", parts: []))
    deploys([ @old ])
    start(rollout_step("resource" => @service.id, "new_deploy" => { "commit" => NEW }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole
    assert_equal "Waiting for f23b4dc to deploy to web (live now: cf0bcbe since #{clock(@old.finished_at)}).", step.summary

    named = Deploys::Deploy.new(id: "dep-named", commit: NEW, status: History::SUCCEEDED, live: true, started_at: @began + 4.minutes, finished_at: @began + 6.minutes)
    deploys([ named, @old.with(live: false) ])
    travel(7.minutes) { check!(watch) }

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal "f23b4dc is live on web (finished #{clock(@began + 6.minutes)}).", step.reason
    assert_match "f23b4dc is live on web", watch.reload.outcome
  end

  test "a watch that runs out of time before its deploy came says what it was waiting for" do
    deploys([ @old ])
    start(rollout_step("resource" => @service.id, "new_deploy" => { "commit" => NEW }))
    watch = @conversation.chat.watches.sole

    travel(Chat::Watch::LONGEST + 1.minute) { check!(watch) }

    assert_equal Chat::Watch::STATUS_TIMED_OUT, watch.reload.status
    assert_match "Last I saw: Production web rollout: Waiting for f23b4dc to deploy to web", watch.outcome
    assert_no_match "nothing seen yet", watch.outcome
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

  test "a newer deploy to staging is not the new production deploy, unless staging is the environment named" do
    production = @old.with(environment: "production")
    staging_old = Deploys::Deploy.new(id: "dep-staging-old", commit: "5555555aaaaaaa", status: History::SUCCEEDED, live: true,
                                      started_at: @began - 1.hour, environment: "staging")
    deploys([ staging_old, production ])
    start(rollout_step)
    start(rollout_step("label" => "Staging rollout", "new_deploy" => { "environment" => "staging" }))
    watches = @conversation.chat.watches.order(:created_at).to_a
    to_production, to_staging = watches.map { |watch| watch.steps.sole }
    assert_equal [ "dep-old", "dep-staging-old" ], [ to_production.deploy_baseline.id, to_staging.deploy_baseline.id ]

    staging = Deploys::Deploy.new(id: "dep-staging", commit: NEW, status: History::SUCCEEDED, live: true, started_at: @began + 1.minute,
                                  finished_at: @began + 2.minutes, environment: "staging")
    deploys([ staging, staging_old.with(live: false), production ])
    travel(3.minutes) { watches.each { |watch| check!(watch) } }

    assert_equal Chat::Watch::Step::STATUS_WAITING, to_production.reload.status, "a deploy to staging is not production's"
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, to_staging.reload.status
  end

  test "the commit named failing ends the step failed at once" do
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "commit" => NEW }))
    watch = @conversation.chat.watches.sole

    deploys([ deploy("A", NEW, History::FAILED, 1, finished: 3), @old ])
    travel(4.minutes) { check!(watch) }

    assert_equal [ Chat::Watch::Step::STATUS_FAILED, "The new deploy of web failed (f23b4dc)." ], [ watch.steps.sole.reload.status, watch.steps.sole.reason ]
    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
  end

  test "A cancelled before B appears keeps the step waiting, and B going live ends it" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    a = deploy("A", "aaaaaaa1111111", History::CANCELLED, 1, finished: 2)
    deploys([ a, @old ])
    travel(3.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status
    assert_equal "The new deploy of web (aaaaaaa) was cancelled. Waiting for the next one.", step.summary
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status

    b = deploy("B", "bbbbbbb2222222", History::RUNNING, 4, live: true)
    deploys([ b, a, @old ])
    travel(5.minutes) { check!(watch) }
    assert_equal [ Chat::Watch::Step::STATUS_RUNNING, "B" ], [ step.reload.status, step.followed_run_id ]

    deploys([ b.with(status: History::SUCCEEDED, finished_at: @began + 6.minutes), a, @old.with(live: false) ])
    travel(7.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
  end

  test "A cancelled because B replaced it says so, and B is followed" do
    deploys([ @old ])
    start(rollout_step("new_deploy" => { "branch" => "main" }))
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    a = deploy("A", "aaaaaaa1111111", History::CANCELLED, 1, finished: 2, branch: "main")
    other = deploy("C", "ccccccc3333333", History::RUNNING, 2, branch: "preview")
    deploys([ other, a, @old ])
    travel(3.minutes) { check!(watch) }

    assert_equal "The new deploy of web (aaaaaaa) was replaced by a newer deploy. Waiting for the next one.", step.reload.summary
  end

  test "A failed is told once while the step stays open, and B, a fix, going live ends it done" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    a = deploy("A", "aaaaaaa1111111", History::FAILED, 1, finished: 2)
    deploys([ a, @old ])
    travel(3.minutes) { check!(watch) }
    travel(4.minutes) { check!(watch) }
    assert_equal Chat::Watch::STATUS_ACTIVE, watch.reload.status
    assert_not step.reload.over?
    assert_equal [ "The new deploy of web failed (aaaaaaa)." ], watch.updates.where(kind: Chat::Watch::Update::KIND_PART_FAILED).map(&:text),
                 "said at once, and once"
    assert_equal "The new deploy of web failed (aaaaaaa). Waiting for a newer deploy until the time limit.", step.summary

    b = deploy("B", "bbbbbbb2222222", History::SUCCEEDED, 5, finished: 6, live: true)
    deploys([ b, a, @old.with(live: false) ])
    travel(7.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
  end

  test "A failed with nothing newer by the time limit ends the watch failed" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    deploys([ deploy("A", "aaaaaaa1111111", History::FAILED, 1, finished: 2), @old ])
    travel(3.minutes) { check!(watch) }

    travel_to(watch.reload.expires_at + 1.minute) { check!(watch) }

    assert_equal Chat::Watch::STATUS_FAILED, watch.reload.status
    assert_match "The new deploy of web failed (aaaaaaa). Nothing newer went out before the time limit.", watch.outcome
    assert_equal Chat::Watch::Step::STATUS_FAILED, watch.steps.sole.status
  end

  test "A live then B started finishes on A when nothing is named, and waits for B when B's commit is named" do
    deploys([ @old ])
    start(rollout_step)
    start(rollout_step("label" => "B rollout", "new_deploy" => { "commit" => "bbbbbbb2222222" }))
    any, named = @conversation.chat.watches.order(:created_at).to_a

    a = deploy("A", "aaaaaaa1111111", History::SUCCEEDED, 1, finished: 2, live: true)
    b = deploy("B", "bbbbbbb2222222", History::RUNNING, 3, live: true)
    deploys([ b, a, @old.with(live: false) ])
    travel(4.minutes) { [ any, named ].each { |watch| check!(watch) } }

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, any.steps.sole.reload.status
    assert_equal [ Chat::Watch::Step::STATUS_RUNNING, "B" ], [ named.steps.sole.reload.status, named.steps.sole.followed_run_id ]

    deploys([ b.with(status: History::SUCCEEDED, finished_at: @began + 5.minutes), a.with(live: false), @old.with(live: false) ])
    travel(6.minutes) { check!(named) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, named.steps.sole.reload.status
  end

  test "A and B rolling out together follow B, the newer, whatever order the provider lists them in" do
    deploys([ @old ])
    start(rollout_step)
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    a = deploy("A", "aaaaaaa1111111", History::RUNNING, 1)
    b = deploy("B", "bbbbbbb2222222", History::RUNNING, 2)
    deploys([ a, b, @old ])
    travel(3.minutes) { check!(watch) }
    assert_equal [ Chat::Watch::Step::STATUS_RUNNING, "B" ], [ step.reload.status, step.followed_run_id ]
    assert_match "bbbbbbb", step.summary

    deploys([ a.with(status: History::CANCELLED, finished_at: @began + 3.minutes), b.with(status: History::SUCCEEDED, finished_at: @began + 4.minutes, live: true),
              @old.with(live: false) ])
    travel(5.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
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

  # A deploy that started minutes after the watch began, and finished minutes after it when finished is given.
  def deploy(id, commit, status, started, finished: nil, live: nil, branch: nil)
    Deploys::Deploy.new(id: id, commit: commit, status: status, live: live, branch: branch, started_at: @began + started.minutes,
                        finished_at: (@began + finished.minutes if finished))
  end

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
