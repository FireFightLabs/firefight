require "test_helper"

# Seen in a real chat: a step reading web's status with the goal "The latest production web rollout is completed and
# serving" read 8 seconds after the watch began, found the previous release's rollout complete and marked itself done
# before the new release was built. Only Northflank's API is stubbed. The pack, the gateway, the capability routing and
# the watch run as they do in production, and the model is sure it is done on every reading, as it was then.
class Conversation::RolloutWatchTest < ActiveSupport::TestCase
  include SlackClientStubHelper
  include ActiveJob::TestHelper

  NorthflankApi = Integrations::NorthflankApi
  Pack = Integrations::Packs::Northflank
  OLD = "cf0bcbe400e34759df35b4011771aa8c776ca049".freeze
  NEW = "f23b4dc3fe04aa11bb22cc33dd44ee55ff667788".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    Pack.store_credentials!(@row, Pack::API_TOKEN => "nf-token")
    @row.store_fields!(Pack::PROJECT => "firefight")
    Integrations::DiscoveryService.sync!(integration)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "firefight-labs/firefight", kind: ResourceMap::KIND_SERVICE,
                                  external_id: "web", name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    listed = ->(items) { Integrations::Pages::Read.new(items: items, complete: true) }
    NorthflankApi.any_instance.stubs(:services).returns(listed.call([ { "id" => "web", "name" => "web", "serviceType" => "deployment" } ]))
    %i[addons jobs workflows].each { |kind| NorthflankApi.any_instance.stubs(kind).returns(listed.call([])) }
    stub_post_message
    Investigation.stubs(:unavailable_reason).returns(nil)
    FirefightAi::WatchJudge.any_instance.stubs(:reading).returns(
      FirefightAi::WatchJudge::Reading.new(state: "done", said: "web's latest production rollout is completed and serving.", parts: [])
    )
    @old_at = Time.utc(2026, 10, 11, 10, 24, 50)
  end

  test "the previous release's finished rollout never ends the step, and the new release's rollout of another commit does" do
    northflank([ deployment("dep-old", OLD, @old_at, active: true) ], rollout: "COMPLETED", since: @old_at + 4.seconds, commit: OLD)
    Conversation::Watches.start(@turn, { "title" => "Firefight production release", "steps" => [
      { "label" => "Production web rollout", "capability" => "resource_status", "resource" => "web", "connection" => "northflank",
        "goal" => "The latest production web rollout is completed and serving" }
    ] })
    watch = @conversation.chat.watches.sole
    step = watch.steps.sole

    travel(8.seconds) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_WAITING, step.reload.status
    assert_equal "Waiting for a new deploy of web to start (live now: cf0bcbe since 10:24 UTC).", Chat::Watch::Shown.step_line(step)

    began = Time.current + 9.minutes
    northflank([ deployment("dep-new", NEW, began, active: true), deployment("dep-old", OLD, @old_at, active: false) ],
               rollout: "COMPLETED", since: @old_at + 4.seconds, commit: OLD)
    travel(10.minutes) { check!(watch) }
    assert_equal Chat::Watch::Step::STATUS_RUNNING, step.reload.status, "the rollout that completed is the old one, so the new one still goes"

    northflank([ deployment("dep-new", NEW, began, active: true), deployment("dep-old", OLD, @old_at, active: false) ],
               rollout: "COMPLETED", since: began + 90.seconds, commit: NEW)
    travel(12.minutes) { check!(watch) }

    assert_equal Chat::Watch::Step::STATUS_SUCCEEDED, step.reload.status
    assert_equal Chat::Watch::STATUS_SUCCEEDED, watch.reload.status
    assert Ability::Invocation.where(workspace: @workspace, action_key: "northflank.list_deployments").exists?
  end

  private

  def deployment(id, commit, created, active:)
    { "id" => id, "createdAt" => created.utc.iso8601, "active" => active, "instances" => 1, "commit" => { "sha" => commit, "message" => "Release" } }
  end

  def northflank(deployments, rollout:, since:, commit:)
    NorthflankApi.any_instance.stubs(:deployments).returns(deployments)
    NorthflankApi.any_instance.stubs(:service).returns(
      "serviceType" => "deployment",
      "status" => { "deployment" => { "status" => rollout, "reason" => "DEPLOYING", "lastTransitionTime" => since.utc.iso8601 } },
      "deployment" => { "instances" => 1, "internal" => { "repository" => "https://github.com/acme/firefight", "branch" => "main", "deployedSHA" => commit } }
    )
  end

  def check!(watch)
    Chat::Watch.where(id: watch.id).update_all(check_claimed_at: nil, checked_at: nil, next_check_at: nil)
    Conversation::Watches.check!(watch.reload)
  end
end
