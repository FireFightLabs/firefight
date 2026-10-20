require "test_helper"

module Integrations
  module MapEventSources
    class PlanetscaleTest < ActiveSupport::TestCase
      # The branch.ready payload PlanetScale's reference shows (planetscale.com/docs/api/webhook-events, Branch ready), cut
      # to the fields read, and a deploy request's.
      BRANCH_READY = { "timestamp" => 1_698_252_879, "event" => "branch.ready", "organization" => "myorg", "database" => "example_database",
                       "resource" => { "id" => "ecrmjy2f4a5o", "type" => "Branch", "name" => "dev", "state" => "ready", "production" => false } }.freeze
      DEPLOY_REQUEST = { "timestamp" => 1_698_252_899, "event" => "deploy_request.schema_applied", "organization" => "myorg",
                         "database" => "example_database",
                         "resource" => { "id" => "4xsz0ql82y4n", "type" => "DeployRequest", "branch" => "dev", "into_branch" => "main", "branch_deleted" => false } }.freeze
      SECRET = "8e46bd50ca092655b1efdfca329f0d79eb976714030a8bfa031397eb0d1cb433".freeze

      test "a delivery whose X-PlanetScale-Signature is the HMAC-SHA256 hex digest of its body is PlanetScale's, and no other is" do
        body = BRANCH_READY.to_json
        signature = OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)

        assert Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => signature }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body.sub("dev", "prod"), headers: { "X-PlanetScale-Signature" => signature }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "another", body) }, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: {}, secret: SECRET)
        assert_not Planetscale.verify(raw_body: body, headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "", body) }, secret: nil)
      end

      test "a branch event names the branch, a deploy request the branch it deploys into, and a closed one that deleted its branch that branch" do
        ready = Planetscale.events(BRANCH_READY, headers: {}).sole
        assert_equal ResourceMap::Scope.new(account: "myorg", kind: ResourceMap::KIND_BRANCH, external_id: "example_database/dev"), ready.scope
        assert_equal [ ResourceMap::Event::ADDED, Time.zone.at(1_698_252_879) ], [ ready.action, ready.at ]
        assert_equal ready.id, Planetscale.events(JSON.parse(BRANCH_READY.to_json), headers: {}).sole.id, "a redelivery is the same event"

        sleeping = Planetscale.events(BRANCH_READY.merge("event" => "branch.sleeping"), headers: {}).sole
        assert_equal ResourceMap::Event::UPDATED, sleeping.action

        applied = Planetscale.events(DEPLOY_REQUEST, headers: {}).sole
        assert_equal "example_database/main", applied.scope.external_id
        closed = DEPLOY_REQUEST.merge("event" => "deploy_request.closed", "resource" => DEPLOY_REQUEST["resource"].merge("branch_deleted" => true))
        assert_equal "example_database/dev", Planetscale.events(closed, headers: {}).sole.scope.external_id

        %w[webhook.test branch.anomaly backup.succeeded keyspace.storage].each do |type|
          assert_empty Planetscale.events(BRANCH_READY.merge("event" => type), headers: {}), "#{type} changes nothing on the map"
        end
        assert_empty Planetscale.events(BRANCH_READY.except("database"), headers: {})
      end

      test "a deploy request moving wakes watches, and one that applied or errored is a deploy that ended" do
        request = DEPLOY_REQUEST.merge("resource" => DEPLOY_REQUEST["resource"].merge("number" => 7, "html_url" => "https://app.planetscale.com/myorg/example_database/deploy-requests/7"))

        assert Planetscale.wakes?(request, headers: {})
        assert_not Planetscale.wakes?(BRANCH_READY, headers: {})
        ended = Planetscale.runs_ended(request, headers: {}).sole
        assert_equal [ RunsEnded::KIND_DEPLOY, RunsEnded::OUTCOME_SUCCEEDED, "deploy request #7", "example_database/main", "main" ],
                     [ ended.kind, ended.outcome, ended.name, ended.place, ended.environment ]
        assert_equal RunsEnded::OUTCOME_FAILED, Planetscale.runs_ended(request.merge("event" => "deploy_request.errored"), headers: {}).sole.outcome
        assert_empty Planetscale.runs_ended(request.merge("event" => "deploy_request.queued"), headers: {})
      end

      test "Firefight adds its webhook to each database on the map when the connection reaches PlanetScale's API, keeping each secret" do
        row = connection
        url = "https://firefight.example/api/v1/map_events/token"
        assert_not Planetscale.registers_for?(row), "a service token without its id reaches only the server"
        row.store_fields!(Packs::Planetscale::TOKEN_ID => "tok123")
        assert Planetscale.registers_for?(row)

        PlanetscaleApi.any_instance.stubs(:webhooks).with("myorg", "shop").returns([ { "id" => "w0", "url" => "https://elsewhere.example", "events" => [] } ])
        PlanetscaleApi.any_instance.stubs(:webhooks).with("myorg", "blog").returns([ { "id" => "w9", "url" => url, "events" => Planetscale::EVENTS, "secret" => "blog-secret" } ])
        PlanetscaleApi.any_instance.expects(:create_webhook).with("myorg", "shop", url: url, events: Planetscale::EVENTS).returns({ "id" => "w1", "secret" => "shop-secret" })
        PlanetscaleApi.any_instance.expects(:update_webhook).never

        assert Planetscale.register_again?(row, url: url)
        webhook = Planetscale.register(row, url: url)
        assert_equal [ Planetscale::ALL_DATABASES, "blog-secret\nshop-secret" ], [ webhook.id, webhook.secret ]
        assert_nil Planetscale.confirmation_for(row, url: url)
      end

      test "a database whose webhooks would be full is asked about first, and a refusal on every database is said" do
        row = connection
        row.store_fields!(Packs::Planetscale::TOKEN_ID => "tok123")
        url = "https://firefight.example/api/v1/map_events/token"
        others = 4.times.map { |index| { "id" => "o#{index}", "url" => "https://other#{index}.example" } }
        PlanetscaleApi.any_instance.stubs(:webhooks).returns(others)

        assert_match "would take the last of the 5 webhooks PlanetScale allows on myorg/blog and myorg/shop", Planetscale.confirmation_for(row, url: url)
        PlanetscaleApi.any_instance.stubs(:create_webhook).raises(PlanetscaleApi::Refused, "PlanetScale answered 422: too many webhooks")
        error = assert_raises(MapEventSource::Refused) { Planetscale.register(row, url: url) }
        assert_match "myorg/shop: PlanetScale answered 422: too many webhooks", error.message

        row.update!(map_events_secret: "stale-secret")
        PlanetscaleApi.any_instance.stubs(:webhooks).with("myorg", "shop").returns([ { "id" => "w9", "url" => url, "events" => [], "secret" => "shop-old-secret" } ])
        PlanetscaleApi.any_instance.stubs(:update_webhook).raises(PlanetscaleApi::Refused, "PlanetScale answered 403: Forbidden")
        PlanetscaleApi.any_instance.stubs(:create_webhook).with("myorg", "blog", url: url, events: Planetscale::EVENTS).returns({ "id" => "w2", "secret" => "blog-secret" })
        assert_equal "blog-secret\nshop-old-secret", Planetscale.register(row, url: url).secret,
                     "a refused database's own webhook keeps its secret, and no other secret saved before is kept"

        PlanetscaleApi.any_instance.stubs(:webhooks).with("myorg", "shop").raises(PlanetscaleApi::Refused, "PlanetScale answered 403: Forbidden")
        assert_equal "blog-secret", Planetscale.register(row, url: url).secret, "a database whose webhooks cannot be listed is refused alone"
      end

      test "an admin adds a webhook to each database, each with a secret of its own, so every one saved counts" do
        assert Planetscale.many_secrets?
        assert_match "hourly sweep", Planetscale.limits
        assert Planetscale::EVENTS.all? { |type| Planetscale.setup_steps.join(" ").include?(type) }
      end

      private

      def connection
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale",
                                                                            settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
        row = integration.integration_environments.create!(credentials: IntegrationEnvironment.token_credentials("Bearer pscale_tkn_secret"))
        databases = %w[shop blog].map do |name|
          ResourceMap::Found.new(provider: "planetscale", account: "myorg", kind: ResourceMap::KIND_DATABASE, external_id: name, name: name)
        end
        ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: databases))
        row
      end
    end
  end
end
