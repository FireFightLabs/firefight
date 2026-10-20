require "test_helper"

module Integrations
  module Packs
    class PlanetscaleTest < ActiveSupport::TestCase
      # A deploy request as PlanetScale's API answers one (DatabaseDeployRequest and its Deployment), cut to the fields read.
      REQUEST = {
        "number" => 7, "branch" => "add-index", "into_branch" => "main", "state" => "closed", "deployment_state" => "complete_pending_revert",
        "approved" => true, "html_url" => "https://app.planetscale.com/acme/shop/deploy-requests/7", "actor" => { "display_name" => "Maya Ortiz" },
        "created_at" => "2026-10-20T09:00:00Z", "deployed_at" => "2026-10-20T09:12:00Z",
        "deployment" => { "state" => "complete_pending_revert", "queued_at" => "2026-10-20T09:05:00Z", "started_at" => "2026-10-20T09:06:00Z",
                          "finished_at" => "2026-10-20T09:12:00Z", "lint_errors" => [] }
      }.freeze
      OPERATIONS = [
        { "id" => "op1", "state" => "complete", "keyspace_name" => "shop", "table_name" => "orders", "operation_name" => "ALTER",
          "ddl_statement" => "ALTER TABLE orders ADD INDEX idx_customer (customer_id)", "progress_percentage" => 100.0,
          "created_at" => "2026-10-20T09:06:00Z", "updated_at" => "2026-10-20T09:11:00Z" },
        { "id" => "op2", "state" => "error", "keyspace_name" => "shop", "table_name" => "carts", "operation_name" => "ALTER",
          "deploy_errors" => "Duplicate key name 'idx_user'", "deploy_error_docs_url" => "https://planetscale.com/docs/errors/1",
          "created_at" => "2026-10-20T09:06:00Z", "updated_at" => "2026-10-20T09:08:00Z" }
      ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
                                                       settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
        @row = @integration.integration_environments.create!(credentials: IntegrationEnvironment.token_credentials("Bearer pscale_tkn_secret"))
        @row.store_fields!(Planetscale::TOKEN_ID => "tok123")
        @pack = Planetscale.new(@integration)
      end

      test "the API is reached with a sign-in as it is, and with a service token as its id and secret" do
        assert_equal "tok123:pscale_tkn_secret", Planetscale.authorization(@row)
        assert Planetscale.reaches_api?(@row)

        @row.store_fields!({})
        error = assert_raises(NativePack::Error) { Planetscale.authorization(@row) }
        assert_match "takes the token's id beside its secret", error.message
        assert_not Planetscale.reaches_api?(@row.reload)

        @row.store_oauth!("access_token" => "oauth-token", "expires_at" => 1.hour.from_now.iso8601)
        assert_equal "Bearer oauth-token", Planetscale.authorization(@row)
        assert Planetscale.reaches_api?(@row)
      end

      test "the pack sits beside the server, its reads read and its changes asked for, a cancel a stopping tool" do
        assert Planetscale.beside_server?
        reads = Planetscale.tool_definitions.select(&:read_only).map(&:name)
        assert_equal %w[planetscale_list_deploy_requests planetscale_get_deploy_request planetscale_list_branch_changes], reads
        assert_includes IntegrationProvider.find("planetscale").stopping_tools, "planetscale_cancel_deploy_request"
      end

      test "deploy requests list newest first with their state and page, and carry their runs and deploys as data" do
        PlanetscaleApi.any_instance.expects(:deploy_requests).with("acme", "shop", into_branch: "main", state: nil, per_page: 20).returns([ REQUEST ])

        result = call(:planetscale_list_deploy_requests, "organization" => "acme", "database" => "shop", "into_branch" => "main")
        text = result["content"].sole["text"]

        assert_match "Latest 1 deploy requests of shop into main, newest first.", text
        assert_match "#7 add-index into main, closed, deployment complete_pending_revert, by Maya Ortiz", text
        run = Capabilities::History.runs_of(result).sole
        assert_equal [ "7", Capabilities::History::SUCCEEDED, 360, "add-index" ], [ run.id, run.status, run.seconds, run.title ]
        assert_equal REQUEST["html_url"], run.url
        deploy = Capabilities::Deploys.deploys_of(result).sole
        assert_equal [ "7", "add-index", Capabilities::History::SUCCEEDED ], [ deploy.id, deploy.branch, deploy.status ]
      end

      test "one deploy request reads its schema changes with the error PlanetScale gave, each one a part of its run" do
        PlanetscaleApi.any_instance.expects(:deploy_request).with("acme", "shop", 7).returns(REQUEST)
        PlanetscaleApi.any_instance.expects(:deploy_operations).with("acme", "shop", 7).returns(OPERATIONS)

        result = call(:planetscale_get_deploy_request, "organization" => "acme", "database" => "shop", "number" => "#7")
        text = result["content"].sole["text"]

        assert_match "Deploy request #7 of shop: add-index into main, closed, deployment complete_pending_revert, approved", text
        assert_match "The revert window is open, so planetscale_revert_deploy_request puts the schema back", text
        assert_match "- ALTER shop.carts: error, error: Duplicate key name 'idx_user'", text
        assert text.end_with?(REQUEST["html_url"])
        failed = Capabilities::History.runs_of(result).sole.first_failed_part
        assert_equal [ "ALTER shop.carts", "Duplicate key name 'idx_user'" ], [ failed.name, failed.detail ]
      end

      test "a deploy request PlanetScale does not have is said by its number" do
        PlanetscaleApi.any_instance.stubs(:deploy_request).raises(PlanetscaleApi::NotFound, "PlanetScale answered 404: Not Found")

        error = assert_raises(NativePack::Error) { call(:planetscale_get_deploy_request, "organization" => "acme", "database" => "shop", "number" => 9) }
        assert_equal "shop has no deploy request #9.", error.message
      end

      test "a Postgres branch's changes and a Vitess branch's resizes and config changes read as runs" do
        PlanetscaleApi.any_instance.stubs(:database).returns({ "kind" => "postgresql" })
        PlanetscaleApi.any_instance.expects(:branch_changes).returns([
          { "id" => "c1", "state" => "completed", "started_at" => "2026-10-19T10:00:00Z", "completed_at" => "2026-10-19T10:20:00Z",
            "previous_cluster_name" => "PS_10", "cluster_name" => "PS_20", "previous_replicas" => 2, "replicas" => 2, "actor" => { "display_name" => "Ana" } }
        ])
        result = call(:planetscale_list_branch_changes, "organization" => "acme", "database" => "shop", "branch" => "main")
        run = Capabilities::History.runs_of(result).sole
        assert_equal [ "branch change", Capabilities::History::SUCCEEDED, 1200, "cluster PS_10 to PS_20, by Ana" ], [ run.name, run.status, run.seconds, run.detail ]

        PlanetscaleApi.any_instance.stubs(:database).returns({ "kind" => "mysql" })
        PlanetscaleApi.any_instance.expects(:branch_resizes).returns([ { "id" => "r1", "state" => "resizing", "created_at" => "2026-10-20T08:00:00Z", "vtgate_name" => "VTG_10" } ])
        PlanetscaleApi.any_instance.expects(:branch_config_changes).returns([ { "id" => "g1", "state" => "failed", "change_type" => "vtgate", "error_message" => "invalid option",
                                                                              "created_at" => "2026-10-18T08:00:00Z" } ])
        PlanetscaleApi.any_instance.expects(:keyspace_resizes).with("acme", "shop", "main", "shop").returns([])
        runs = Capabilities::History.runs_of(call(:planetscale_list_branch_changes, "organization" => "acme", "database" => "shop", "branch" => "main", "keyspace" => "shop"))
        assert_equal [ [ "resize", Capabilities::History::RUNNING ], [ "config change", Capabilities::History::FAILED ] ], runs.map { |each| [ each.name, each.status ] }
        assert_match "invalid option", runs.last.detail
      end

      test "a resize goes to a Postgres branch's cluster, a Vitess keyspace or its VTGates, and refuses what the engine does not take" do
        PlanetscaleApi.any_instance.stubs(:database).returns({ "kind" => "postgresql" })
        PlanetscaleApi.any_instance.expects(:change_branch).with("acme", "shop", "main", { "cluster_size" => "PS_80", "replicas" => 3 }).returns({ "state" => "queued" })
        text = call(:planetscale_resize_branch, "organization" => "acme", "database" => "shop", "branch" => "main", "cluster_size" => "PS_80", "replicas" => 3)["content"].sole["text"]
        assert_match "PlanetScale took the change to shop/main (queued).", text
        assert_raises(NativePack::Error) { call(:planetscale_resize_branch, "organization" => "acme", "database" => "shop", "branch" => "main", "keyspace" => "shop") }

        PlanetscaleApi.any_instance.stubs(:database).returns({ "kind" => "mysql" })
        PlanetscaleApi.any_instance.expects(:resize_keyspace).with("acme", "shop", "main", "shop", { "cluster_size" => "PS_80" }).returns({})
        call(:planetscale_resize_branch, "organization" => "acme", "database" => "shop", "branch" => "main", "keyspace" => "shop", "cluster_size" => "PS_80")
        error = assert_raises(NativePack::Error) { call(:planetscale_resize_branch, "organization" => "acme", "database" => "shop", "branch" => "main", "cluster_size" => "PS_80") }
        assert_match "sized per keyspace", error.message
      end

      test "each change to a deploy request's run is its own call, and a refusal says the token may lack the access" do
        PlanetscaleApi.any_instance.expects(:act_on_deploy_request).with("acme", "shop", 7, "revert").returns(REQUEST.merge("deployment_state" => "in_progress_revert"))
        text = call(:planetscale_revert_deploy_request, "organization" => "acme", "database" => "shop", "number" => 7)["content"].sole["text"]
        assert_match "PlanetScale is reverting deploy request #7. Its status says when the schema is back. Its deployment is in_progress_revert now.", text

        PlanetscaleApi.any_instance.stubs(:act_on_deploy_request).raises(PlanetscaleApi::Refused, "PlanetScale answered 403: Forbidden")
        error = assert_raises(NativePack::Error) { call(:planetscale_cancel_deploy_request, "organization" => "acme", "database" => "shop", "number" => 7) }
        assert_equal "PlanetScale answered 403: Forbidden. The connection's token may lack the access this needs, which its owner grants in PlanetScale.", error.message
      end

      test "whoever opened a deploy request is asked before a cancel stops it" do
        PlanetscaleApi.any_instance.stubs(:deploy_request).returns(REQUEST)

        owner = @pack.owner_of("planetscale_cancel_deploy_request", environment_row: @row, arguments: { "organization" => "acme", "database" => "shop", "number" => 7 })
        assert_equal [ "Maya Ortiz", Owner::ROLE_CREATED, "deploy request #7 of shop" ], [ owner.name, owner.role, owner.what ]
        assert_nil @pack.owner_of("planetscale_revert_deploy_request", environment_row: @row, arguments: {})
      end

      private

      def call(tool, arguments) = @pack.call(tool.to_s, environment_row: @row, arguments: arguments)
    end
  end
end
