require "test_helper"

# Cloud Run jobs and Cloud Deploy pipelines and stages, answered through the Google Cloud pack's own tools.
class Integrations::Capabilities::GoogleCloudReleasesTest < ActiveSupport::TestCase
  RUN_ID = "projects/acme-prod/locations/us-central1/services/web".freeze
  JOB_ID = "projects/acme-prod/locations/us-central1/jobs/nightly".freeze
  PIPELINE_ID = "projects/acme-prod/locations/us-central1/deliveryPipelines/web".freeze
  STAGE_ID = "#{PIPELINE_ID}/targets/prod".freeze
  PACK = Integrations::Packs::GoogleCloud

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud", slug: "gcp")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @row.store_fields!("project" => "acme-prod")
    PACK.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    @web = resource!(ResourceMap::KIND_SERVICE, RUN_ID, "web", PACK::TYPE_RUN)
    resource!(ResourceMap::KIND_JOB, JOB_ID, "nightly", PACK::TYPE_JOB)
    resource!(ResourceMap::KIND_PIPELINE, PIPELINE_ID, "web", PACK::TYPE_PIPELINE)
    @stage = resource!(ResourceMap::KIND_RELEASE_FLOW, STAGE_ID, "web prod", PACK::TYPE_STAGE)
  end

  test "a job's run history is its executions, read by its id when named, and its logs narrow to one execution" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "nightly", "run" => "nightly-x2k9p", "limit" => 5)
    assert_equal [ "list_executions", { "resource" => JOB_ID, "run" => "nightly-x2k9p", "limit" => 5 } ], [ history.tool.name, history.arguments ]

    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "nightly", "run" => "nightly-x2k9p", "text" => "error")
    assert_equal [ "search_logs", { "resource" => JOB_ID, "text" => "error", "run" => "nightly-x2k9p" } ], [ logs.tool.name, logs.arguments ]
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "nightly").tool.name
    assert_match "no connection offers a rollback for it", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "nightly", "to" => "x")
  end

  test "a pipeline's and a stage's run history and deploys are their rollouts, and a stage rolls back to a release" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => @stage.id.to_s, "run" => "rel-7/rel-7-to-prod-0001", "name" => "prod")
    assert_equal [ "list_rollouts", { "resource" => STAGE_ID, "run" => "rel-7/rel-7-to-prod-0001", "limit" => 20, "name" => "prod" } ], [ history.tool.name, history.arguments ]
    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web prod", "limit" => 3)
    assert_equal [ "list_rollouts", { "resource" => STAGE_ID, "limit" => 3 } ], [ deploys.tool.name, deploys.arguments ]

    rollback = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web prod", "to" => "rel-6")
    assert_equal [ "rollback_target", { "resource" => STAGE_ID, "release" => "rel-6" } ], [ rollback.tool.name, rollback.arguments ]
    assert_match "no connection offers a rollback for it",
                 unroutable(Integrations::Capabilities::ROLLBACK, "resource" => ResourceMap::Resource.find_by!(external_id: PIPELINE_ID).id.to_s, "to" => "rel-6")
  end

  test "a Cloud Run service's logs keep no runs, and say so rather than read them all" do
    assert_match "leave run out for web", unroutable(Integrations::Capabilities::LOGS, "resource" => RUN_ID, "run" => "x")
    assert Integrations::Capabilities::GoogleCloud.logs_by_run?
  end

  test "the stage that released a service has its rollouts read live for what changed" do
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: @stage, relation: ResourceMap::RELATION_RELEASED_BY,
                              integration_environment: @row, origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    subject = ResourceMap::Timeline.subject(@workspace, map_reader, { "resource" => RUN_ID })
    timeline = ResourceMap::Timeline.new(workspace: @workspace, principal: map_reader, subject: subject, from: 1.day.ago, to: Time.current)

    assert_includes ResourceMap::WhatChanged.targets(timeline), @stage
    run = { "id" => "rel-7/rel-7-to-prod-0001", "name" => "web prod", "status" => "failed", "started_at" => 10.minutes.ago.iso8601, "seconds" => 240,
            "detail" => "release rel-7" }
    assert_equal "web prod run rel-7/rel-7-to-prod-0001 failed, took 4 minutes (release rel-7), from Google Cloud",
                 ResourceMap::Timeline.run_entry(@stage, run, through: "Google Cloud").what
  end

  private

  def resource!(kind, id, name, type)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "google_cloud", account: "acme-prod", kind: kind, external_id: id, name: name,
                                  details: { "type" => type }, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
