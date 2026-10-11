require "test_helper"

class Integrations::Capabilities::NorthflankTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { api_token: "x" }.to_json)
    Integrations::Packs::Northflank.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    @web = resource!(ResourceMap::KIND_SERVICE, "web", "web")
    resource!(ResourceMap::KIND_DATABASE, "db", "db")
  end

  test "run history is a service's builds, and those of the build service it runs builds of" do
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "web", "limit" => 5)
    assert_equal "build_history", history.tool.name
    assert_equal({ "resource" => "web", "limit" => 5 }, history.arguments.slice("resource", "limit"))

    builder = resource!(ResourceMap::KIND_BUILD_SERVICE, "builder", "builder")
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: builder, relation: ResourceMap::RELATION_RUNS_BUILDS_OF,
                              integration_environment: @row, origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    assert_equal "builder", resolve(Integrations::Capabilities::HISTORY, "resource" => "web").arguments["resource"]
    assert_equal "builder", resolve(Integrations::Capabilities::HISTORY, "resource" => "builder").arguments["resource"]
    assert_equal "backup_history", resolve(Integrations::Capabilities::HISTORY, "resource" => "db").tool.name
  end

  test "every tool the adapter runs is one the pack declares, and build history is wrapped" do
    assert_empty Integrations::Capabilities::Northflank::TOOLS.values.flatten - Integrations::Packs::Northflank.tool_definitions.map(&:name)
    assert Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "northflank").tools.find_by!(name: "build_history"))
    assert_match "see how long its runs usually take", Integrations::Capabilities.halon_sentence("northflank", "Northflank")
  end

  test "a workflow's and a release flow's runs, a job's and a database's are their run history, and a named run is passed on" do
    resource!(ResourceMap::KIND_WORKFLOW, "release", "Release")
    resource!(ResourceMap::KIND_RELEASE_FLOW, "shop/production", "shop Production")
    resource!(ResourceMap::KIND_JOB, "nightly", "nightly")
    history = Integrations::Capabilities::HISTORY

    workflow = resolve(history, "resource" => "Release", "run" => "r9")
    flow = resolve(history, "resource" => "shop Production", "name" => "release")
    job = resolve(history, "resource" => "nightly", "run" => "run-77")

    assert_equal [ "workflow_runs", { "workflow" => "release", "run" => "r9" } ], [ workflow.tool.name, workflow.arguments.except("project") ]
    assert_equal [ "release_flow_runs", { "pipeline" => "shop", "stage" => "Production", "name" => "release" } ], [ flow.tool.name, flow.arguments.except("project") ]
    assert_equal [ "job_runs", { "job" => "nightly", "run" => "run-77" } ], [ job.tool.name, job.arguments.except("project") ]
    assert_equal "old-build", resolve(history, "resource" => "web", "run" => "old-build").arguments["run"]
    assert_not Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "northflank").tools.find_by!(name: "job_runs"))
    assert Integrations::Capabilities.wrapped?(@workspace.integrations.find_by!(slug: "northflank").tools.find_by!(name: "workflow_runs"))
  end

  test "a rollback sends the body the service takes: a build, an image with its credentials, or out of a canary rollout" do
    image = resource!(ResourceMap::KIND_SERVICE, "edge", "edge")
    image.update!(details: { "image" => "ghcr.io/acme/edge:1.4", "image_credentials" => "ghcr-pull" })
    rollback = Integrations::Capabilities::ROLLBACK

    assert_equal({ "method" => "POST", "path" => "services/web/deployment", "body" => { "internal" => { "id" => "web", "buildId" => "brave-otter-12" } } },
                 resolve(rollback, "resource" => "web", "to" => "brave-otter-12").arguments.except("project"))
    assert_equal({ "external" => { "imagePath" => "ghcr.io/acme/edge:1.3", "credentials" => "ghcr-pull" } },
                 resolve(rollback, "resource" => "edge", "to" => "ghcr.io/acme/edge:1.3").arguments["body"])
    canary = resolve(rollback, "resource" => "web", "to" => "6560a1b2c3d4e5f6a7b8c9d0").arguments
    assert_equal [ "services/web/rollout/rollback", { "deployment" => "6560a1b2c3d4e5f6a7b8c9d0" } ], canary.values_at("path", "body")
  end

  test "a database restarts and scales its replicas, a job scales by its plan, and a plan goes with any of them" do
    resource!(ResourceMap::KIND_JOB, "nightly", "nightly")
    restart = Integrations::Capabilities::RESTART
    scale = Integrations::Capabilities::SCALE

    assert_equal "addons/db/restart", resolve(restart, "resource" => "db").arguments["path"]
    assert_equal [ "addons/db/scale", { "replicas" => 2 } ], resolve(scale, "resource" => "db", "instances" => 2).arguments.values_at("path", "body")
    assert_equal [ "jobs/nightly/scale", { "deploymentPlan" => "nf-compute-50" } ],
                 resolve(scale, "resource" => "nightly", "instances" => 1, "plan" => "nf-compute-50").arguments.values_at("path", "body")
    assert_equal({ "instances" => 3, "deploymentPlan" => "nf-compute-20" }, resolve(scale, "resource" => "web", "instances" => 3, "plan" => "nf-compute-20").arguments["body"])
    assert_match "Name the plan", assert_raises(Integrations::Capabilities::Unroutable) { resolve(scale, "resource" => "nightly", "instances" => 1) }.message
    assert_match "instances must be 1", assert_raises(Integrations::Capabilities::Unroutable) { resolve(scale, "resource" => "nightly", "instances" => 4, "plan" => "x") }.message
  end

  test "a job's logs are narrowed to one run, which a provider without runs refuses rather than ignores" do
    resource!(ResourceMap::KIND_JOB, "nightly", "nightly")
    logs = Integrations::Capabilities::LOGS

    assert_equal({ "resource" => "nightly", "run" => "run-77" }, resolve(logs, "resource" => "nightly", "run" => "run-77").arguments.except("project", "type"))

    render = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    render_row = render.integration_environments.create!(credentials: { token: "x" }.to_json)
    render.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "render", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "srv-api",
                                  name: "api", integration_environment: render_row, first_seen_at: Time.current, last_seen_at: Time.current)
    error = assert_raises(Integrations::Capabilities::Unroutable) { resolve(logs, "resource" => "api", "run" => "run-1") }
    assert_match "keeps no logs per run for api, so leave run out", error.message
    assert_match "sizes api by instances alone, so leave plan out",
                 assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::SCALE, "resource" => "api", "instances" => 2, "plan" => "pro") }.message
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def resource!(kind, id, name)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
