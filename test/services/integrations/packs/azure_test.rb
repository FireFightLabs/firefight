require "test_helper"

module Integrations
  module Packs
    class AzureTest < ActiveSupport::TestCase
      SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze
      GROUP = "/subscriptions/#{SUBSCRIPTION}/resourceGroups/shop/providers".freeze
      WEB_ID = "#{GROUP}/Microsoft.Web/sites/storefront".freeze
      FUNCTION_ID = "#{GROUP}/Microsoft.Web/sites/jobs".freeze
      APP_ID = "#{GROUP}/Microsoft.App/containerApps/api".freeze
      SQL_ID = "#{GROUP}/Microsoft.Sql/servers/shop-sql/databases/orders".freeze
      PG_ID = "#{GROUP}/Microsoft.DBforPostgreSQL/flexibleServers/catalog".freeze
      PLAN_ID = "#{GROUP}/Microsoft.Web/serverfarms/shop-plan".freeze
      ENVIRONMENT_ID = "#{GROUP}/Microsoft.App/managedEnvironments/shop-env".freeze
      FIELDS = { Azure::TENANT => "contoso.onmicrosoft.com", Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                 Azure::SUBSCRIPTION => SUBSCRIPTION }.freeze
      PORTAL = 'https://portal.azure.com/#@contoso.onmicrosoft.com/resource'.freeze
      SITE = { "id" => WEB_ID, "name" => "storefront", "kind" => "app,linux", "location" => "westeurope",
               "properties" => { "state" => "Running", "serverFarmId" => PLAN_ID, "sku" => "PremiumV3",
                                 "enabledHostNames" => [ "storefront.azurewebsites.net", "storefront.scm.azurewebsites.net", "shop.example.com" ] } }.freeze
      FUNCTION = { "id" => FUNCTION_ID, "name" => "jobs", "kind" => "functionapp,linux", "location" => "westeurope", "properties" => { "state" => "Running" } }.freeze
      APP = { "id" => APP_ID, "name" => "api", "location" => "westeurope",
              "properties" => { "runningStatus" => "Running", "provisioningState" => "Succeeded", "managedEnvironmentId" => ENVIRONMENT_ID,
                                "latestReadyRevisionName" => "api--v2",
                                "configuration" => { "activeRevisionsMode" => "Multiple",
                                                     "ingress" => { "fqdn" => "api.happy.westeurope.azurecontainerapps.io", "targetPort" => 8080,
                                                                    "traffic" => [ { "revisionName" => "api--v2", "weight" => 100 } ] } },
                                "template" => { "containers" => [ { "name" => "api", "image" => "acme.azurecr.io/api:v2" } ], "scale" => { "minReplicas" => 1, "maxReplicas" => 5 } } } }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure")
        @row = @integration.integration_environments.create!
        Azure.store_credentials!(@row, Azure::SECRET => " s3cret ")
        @row.store_fields!(FIELDS)
        @pack = Azure.new(@integration)
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.Web/sites") }.returns(pages([ SITE, FUNCTION ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.App/containerApps") }.returns(pages([ APP ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.Sql/servers") }.returns(pages([ { "id" => "#{GROUP}/Microsoft.Sql/servers/shop-sql", "name" => "shop-sql" } ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/servers/shop-sql/databases") }.returns(pages([
          { "id" => "#{GROUP}/Microsoft.Sql/servers/shop-sql/databases/master", "name" => "master", "properties" => { "status" => "Online" } },
          { "id" => SQL_ID, "name" => "orders", "location" => "westeurope", "sku" => { "name" => "GP_S_Gen5_2" }, "properties" => { "status" => "Online" } }
        ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/flexibleServers") }.returns(pages([
          { "id" => PG_ID, "name" => "catalog", "location" => "westeurope", "sku" => { "name" => "Standard_D2ds_v4" }, "properties" => { "state" => "Ready", "version" => "16" } }
        ]))
        AzureApi.any_instance.stubs(:post).with { |path, *| path.end_with?("/config/appsettings/list", "/config/connectionstrings/list") }.returns({ "properties" => {} })
        AzureApi.any_instance.stubs(:get).with(WEB_ID, Azure::WEB_VERSION).returns(SITE)
        AzureApi.any_instance.stubs(:get).with(FUNCTION_ID, Azure::WEB_VERSION).returns(FUNCTION)
        AzureApi.any_instance.stubs(:get).with(APP_ID, Azure::APP_VERSION).returns(APP)
        AzureApi.any_instance.stubs(:get).with(SQL_ID, Azure::SQL_VERSION).returns({ "id" => SQL_ID, "name" => "orders", "properties" => { "status" => "Online" } })
      end

      test "only the secret is a credential, stored trimmed, and only the three changes are not read only" do
        assert_equal "s3cret", @row.reload.credentials_hash[Azure::SECRET]
        assert_equal %w[rollback_app restart_resource scale_app], Azure.tool_definitions.reject(&:read_only).map(&:name)
      end

      test "a principal or subscription Azure refuses is said before anything is saved" do
        AzureApi.any_instance.stubs(:subscription_details).raises(AzureApi::Error, "Microsoft answered 401: AADSTS7000215: Invalid client secret provided")
        values = { Azure::SECRET => "wrong" }

        assert_match "Azure refused this service principal or subscription 11111111-2222-3333-4444-555555555555: Microsoft answered 401: AADSTS7000215: Invalid client secret provided.", Azure.credential_refusal(values, fields: FIELDS)
        assert_equal "Enter the tenant and client id.", Azure.credential_refusal(values, fields: FIELDS.except(Azure::TENANT))
        assert_equal "Choose at least one subscription, or all the service principal can read.", Azure.credential_refusal(values, fields: FIELDS.except(Azure::SUBSCRIPTION))
        assert_equal "Paste the client secret.", Azure.credential_refusal({}, fields: FIELDS)
        assert_equal [ Azure::SECRET ], Azure.credential_fields.map(&:key)
        subscription = IntegrationProvider.find("azure").connect_fields.find { |field| field.key == Azure::SUBSCRIPTION }
        assert_match "a GUID", subscription.refusal("prod")
      end

      test "a connection in a sovereign cloud reaches that cloud and links to its portal" do
        @integration.update!(settings: @integration.settings.to_h.merge(Integration::REGION_SETTING => "us_government"))
        AzureApi.expects(:new).with { |**options| options[:cloud] == AzureApi::US_GOVERNMENT }.returns(stub(subscription_details: {}, list: pages([]), segment: ""))

        assert_match "https://portal.azure.us/\#@contoso.onmicrosoft.com/resource/subscriptions/#{SUBSCRIPTION}/overview", call(:list_resources)

        AzureApi.expects(:new).with { |**options| options[:cloud] == AzureApi::CHINA }.returns(stub(subscription_details: {}))
        assert_nil Azure.credential_refusal({ Azure::SECRET => "s" }, region: IntegrationProvider.find("azure").region("china"), fields: FIELDS)
      end

      test "every kind is listed with its group and region, a function app told apart from a web app, and master left out" do
        text = call(:list_resources)

        assert_match "storefront (#{WEB_ID}), App Service app in shop, westeurope, running", text
        assert_match "jobs (#{FUNCTION_ID}), Function app in shop", text
        assert_match "api (#{APP_ID}), Container App in shop, westeurope, running", text
        assert_match "orders (#{SQL_ID}), Azure SQL database in shop, westeurope, online", text
        assert_match "catalog (#{PG_ID}), PostgreSQL flexible server in shop, westeurope, ready", text
        assert_no_match "master", text
      end

      test "an App Service app's console logs are read from Log Analytics by its id, with every filter quoted" do
        AzureApi.any_instance.expects(:query_resource_logs).with do |id, query, timespan|
          id == WEB_ID && query.start_with?("AppServiceConsoleLogs | project TimeGenerated") &&
            query.include?('| where Text contains "say \"hi\""') && query.include?('| where Text matches regex "time.?out"') &&
            query.include?('| where Text !contains "health"') && query.end_with?("| order by TimeGenerated desc | take 50") && timespan.include?("/")
        end.returns(table(%w[TimeGenerated Source Text], [ [ "2026-10-03T10:00:00Z", "host-1 Error", "upstream timed out" ] ]))

        text = call(:search_logs, "resource" => "storefront", "text" => 'say "hi"', "regex" => "time.?out", "exclude" => "health", "limit" => 50)

        assert_match "2026-10-03T10:00:00Z host-1 Error upstream timed out", text
        assert_match PORTAL + WEB_ID + "/overview", text
      end

      test "a log table no diagnostic setting fills says how to send it, and PostgreSQL falls back to AzureDiagnostics" do
        AzureApi.any_instance.stubs(:query_resource_logs).with { |_, query, _| query.start_with?("FunctionAppLogs") }
                .raises(AzureApi::Error, "Azure answered 400: Failed to resolve table or column expression named 'FunctionAppLogs'")
        assert_match "Log Analytics has no FunctionAppLogs for jobs, so no diagnostic setting sends them to a workspace yet. The connection works.",
                     call(:search_logs, "resource" => FUNCTION_ID)

        AzureApi.any_instance.stubs(:query_resource_logs).with { |_, query, _| query.start_with?("PGSQLServerLogs") }
                .raises(AzureApi::Error, "Azure answered 400: Failed to resolve table or column expression named 'PGSQLServerLogs'")
        AzureApi.any_instance.stubs(:query_resource_logs).with { |_, query, _| query.start_with?("AzureDiagnostics | where Category == \"PostgreSQLLogs\"") }
                .returns(table(%w[TimeGenerated Source Text], [ [ "2026-10-03T10:00:00Z", "FATAL", "remaining connection slots are reserved" ] ]))
        assert_match "FATAL remaining connection slots are reserved", call(:search_logs, "resource" => PG_ID)
      end

      test "a Container App's logs are read where its environment sends them" do
        AzureApi.any_instance.stubs(:get).with(ENVIRONMENT_ID, Azure::APP_VERSION)
                .returns({ "properties" => { "appLogsConfiguration" => { "destination" => "log-analytics", "logAnalyticsConfiguration" => { "customerId" => "ws-1" } } } })
        AzureApi.any_instance.expects(:query_workspace_logs).with { |workspace, query, _| workspace == "ws-1" && query.start_with?('ContainerAppSystemLogs_CL | where ContainerAppName_s == "api"') }
                .returns(table(%w[TimeGenerated Source Text], [ [ "2026-10-03T10:00:00Z", "api--v2", "Container api failed liveness probe" ] ]))

        assert_match "api--v2 Container api failed liveness probe", call(:search_logs, "resource" => "api", "stream" => "system")

        AzureApi.any_instance.stubs(:get).with(ENVIRONMENT_ID, Azure::APP_VERSION).returns({ "properties" => { "appLogsConfiguration" => { "destination" => "azure-monitor" } } })
        AzureApi.any_instance.expects(:query_resource_logs).with { |id, query, _| id == ENVIRONMENT_ID && query.start_with?('ContainerAppConsoleLogs | where ContainerAppName == "api"') }
                .returns(table(%w[TimeGenerated Source Text], []))
        assert_match "kept only when a diagnostic setting on the Container Apps environment", call(:search_logs, "resource" => "api")
      end

      test "metrics are read from Azure Monitor, a count turned into a rate, cpu read from the App Service plan, and a status class kept apart" do
        AzureApi.any_instance.expects(:metrics).with { |id, query| id == WEB_ID && query["metricnames"] == "Requests" && query["aggregation"] == "total" && query["interval"] == "PT1M" }
                .returns({ "value" => [ { "timeseries" => [ { "data" => [ { "timeStamp" => "2026-10-03T10:00:00Z", "total" => 120 } ] } ] } ] })
        AzureApi.any_instance.expects(:metrics).with { |id, query| id == PLAN_ID && query["metricnames"] == "CpuPercentage" }
                .returns({ "value" => [ { "timeseries" => [ { "data" => [ { "timeStamp" => "2026-10-03T10:00:00Z", "average" => 42.5 } ] } ] } ] })

        result = @pack.call("query_metrics", environment_row: @row, arguments: { "resource" => "storefront", "metrics" => %w[requests cpu], "minutes" => 60 })

        charts = result.dig(Telemetry::STRUCTURED, Telemetry::CHARTS)
        assert_equal [ [ "per minute", 120.0 ], [ "%", 42.5 ] ], charts.map { |chart| [ chart["unit"], chart["series"].first["points"].first.last ] }

        AzureApi.any_instance.expects(:metrics).with { |_, query| query["$filter"] == "statusCodeCategory eq '*'" }.returns({ "value" => [ { "timeseries" => [
          { "metadatavalues" => [ { "name" => { "value" => "statusCodeCategory" }, "value" => "5xx" } ], "data" => [ { "timeStamp" => "2026-10-03T10:00:00Z", "total" => 6 } ] },
          { "metadatavalues" => [ { "name" => { "value" => "statusCodeCategory" }, "value" => "2xx" } ], "data" => [ { "timeStamp" => "2026-10-03T10:00:00Z", "total" => 600 } ] }
        ] } ] })
        assert_match "5xx responses of api (per minute)", call(:query_metrics, "resource" => "api", "metrics" => [ "http_5xx" ], "minutes" => 60)
        assert_match "has no tcp_connections", assert_raises(Integrations::Error) { call(:query_metrics, "resource" => "orders", "metrics" => [ "tcp_connections" ]) }.message
      end

      test "an App Service app's deployments and slots, and a Container App's revisions, show what went out" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{WEB_ID}/deployments" }.returns(pages([
          { "name" => "abc123", "properties" => { "status" => 4, "start_time" => "2026-10-03T09:00:00Z", "author" => "ana", "message" => "Fix checkout\nmore", "active" => true } }
        ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{WEB_ID}/slots" }.returns(pages([ { "name" => "storefront/staging", "properties" => { "state" => "Running" } } ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{APP_ID}/revisions" }.returns(pages([
          { "name" => "api--v2", "properties" => { "createdTime" => "2026-10-03T09:00:00Z", "active" => true, "healthState" => "Healthy", "runningState" => "Running",
                                                   "replicas" => 2, "trafficWeight" => 100, "template" => { "containers" => [ { "image" => "acme.azurecr.io/api:v2" } ] } } }
        ]))

        assert_match "2026-10-03T09:00:00Z, succeeded, active, by ana, \"Fix checkout\", deployment abc123\nDeployment slots, which rollback_app swaps with production: staging (running).",
                     call(:list_deployments, "resource" => "storefront")
        assert_match "2026-10-03T09:00:00Z, api--v2, active, health healthy, running running, 2 replicas, 100% of traffic, image acme.azurecr.io/api:v2",
                     call(:list_deployments, "resource" => "api")
      end

      test "an App Service app's deployments carry their start, end and status as run history" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{WEB_ID}/deployments" }.returns(pages([
          { "name" => "storefront/abc123", "properties" => { "status" => 4, "start_time" => "2026-10-03T09:00:00Z", "end_time" => "2026-10-03T09:05:00Z", "message" => "Fix checkout" } },
          { "name" => "storefront/def456", "properties" => { "status" => 1, "start_time" => "2026-10-03T10:00:00Z" } }
        ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{WEB_ID}/slots" }.returns(pages([]))

        result = Azure.new(@integration).call("list_deployments", environment_row: @row, arguments: { "resource" => "storefront" })

        assert_equal [ [ "def456", "running", nil ], [ "abc123", "succeeded", 300 ] ], Capabilities::History.runs_of(result).map { |run| [ run.id, run.status, run.seconds ] }
      end

      test "a rollback swaps a slot the app has, or sends a Container App's traffic to an earlier revision, activating it first" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{WEB_ID}/slots" }.returns(pages([ { "name" => "storefront/staging" } ]))
        AzureApi.any_instance.expects(:post).with("#{WEB_ID}/slotsswap", Azure::WEB_VERSION, { "targetSlot" => "staging", "preserveVnet" => true }).returns({})
        assert_match "To undo, swap staging with production again.", call(:rollback_app, "resource" => "storefront", "to" => "staging")
        assert_match "has no slot called canary", assert_raises(Integrations::Error) { call(:rollback_app, "resource" => "storefront", "to" => "canary") }.message

        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{APP_ID}/revisions" }.returns(pages([ { "name" => "api--v1", "properties" => { "active" => false } } ]))
        AzureApi.any_instance.expects(:post).with("#{APP_ID}/revisions/api--v1/activate", Azure::APP_VERSION).returns({})
        AzureApi.any_instance.expects(:patch).with do |id, _version, body|
          id == APP_ID && body.dig("properties", "configuration", "ingress", "traffic") == [ { "revisionName" => "api--v1", "weight" => 100 } ] &&
            body.dig("properties", "configuration", "ingress", "targetPort") == 8080
        end.returns({})
        assert_match "Before, it went 100% to api--v2.", call(:rollback_app, "resource" => "api", "to" => "api--v1")
      end

      test "a Container App in single revision mode is not rolled back by traffic, and says what to do instead" do
        single = APP.deep_dup.tap { |app| app["properties"]["configuration"]["activeRevisionsMode"] = "Single" }
        AzureApi.any_instance.stubs(:get).with(APP_ID, Azure::APP_VERSION).returns(single)
        AzureApi.any_instance.expects(:patch).never

        assert_match "single revision mode", assert_raises(Integrations::Error) { call(:rollback_app, "resource" => "api", "to" => "api--v1") }.message
      end

      test "a restart reaches each kind as Azure offers it, and Azure SQL has none" do
        AzureApi.any_instance.expects(:post).with("#{WEB_ID}/restart", Azure::WEB_VERSION).returns({})
        AzureApi.any_instance.expects(:post).with("#{PG_ID}/restart", Azure::POSTGRES_VERSION).returns({})
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "#{APP_ID}/revisions" }.returns(pages([ { "name" => "api--v2", "properties" => { "active" => true } },
                                                                                                    { "name" => "api--v1", "properties" => { "active" => false } } ]))
        AzureApi.any_instance.expects(:post).with("#{APP_ID}/revisions/api--v2/restart", Azure::APP_VERSION).returns({})

        assert_match "Azure is restarting storefront.", call(:restart_resource, "resource" => "storefront")
        assert_match "restarting PostgreSQL flexible server catalog", call(:restart_resource, "resource" => "catalog")
        assert_match "active revision api--v2", call(:restart_resource, "resource" => "api")
        assert_match "Azure SQL has no restart", assert_raises(Integrations::Error) { call(:restart_resource, "resource" => "orders") }.message
      end

      test "scaling sets a plan's instance count, naming the apps that share it, or a Container App's replicas, and refuses what cannot work" do
        plan = { "id" => PLAN_ID, "name" => "shop-plan", "sku" => { "name" => "P1v3", "tier" => "PremiumV3", "capacity" => 2 }, "properties" => { "numberOfSites" => 3 } }
        AzureApi.any_instance.stubs(:get).with(PLAN_ID, Azure::WEB_VERSION).returns(plan)
        AzureApi.any_instance.expects(:put).with { |id, _, body| id == PLAN_ID && body["sku"]["capacity"] == 4 && body["sku"]["name"] == "P1v3" }.returns({})
        assert_match "from 2 to 4 instances. It is shared by 3 apps, and each now runs on 4 instances. To undo, set it back to 2.",
                     call(:scale_app, "resource" => "storefront", "instances" => 4)

        AzureApi.any_instance.expects(:patch).with { |id, _, body| id == APP_ID && body.dig("properties", "template", "scale") == { "minReplicas" => 3, "maxReplicas" => 5 } &&
                                                      body.dig("properties", "template", "containers").present? }.returns({})
        assert_match "between 3 and 5 replicas", call(:scale_app, "resource" => "api", "instances" => 3)
        assert_match "cannot be above the most (5)", assert_raises(Integrations::Error) { call(:scale_app, "resource" => "api", "min_replicas" => 9) }.message

        AzureApi.any_instance.stubs(:get).with(PLAN_ID, Azure::WEB_VERSION).returns(plan.merge("sku" => { "tier" => "Dynamic" }))
        assert_match "adds and removes instances on its own", assert_raises(Integrations::Error) { call(:scale_app, "resource" => "storefront", "instances" => 2) }.message
      end

      test "two resources of one name are refused with both ids rather than one chosen" do
        twin = SITE.merge("id" => "/subscriptions/#{SUBSCRIPTION}/resourceGroups/other/providers/Microsoft.Web/sites/storefront")
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.Web/sites") }.returns(pages([ SITE, twin ]))

        error = assert_raises(Integrations::Error) { call(:describe_resource, "resource" => "storefront") }
        assert_equal "More than one Azure resource is called storefront: #{WEB_ID}, #{twin['id']}. Name it by its id.", error.message
      end

      test "a resource in another subscription is never reached" do
        AzureApi.any_instance.expects(:post).never

        error = assert_raises(Integrations::Error) { call(:restart_resource, "resource" => "/subscriptions/99999999-2222-3333-4444-555555555555/resourceGroups/x/providers/Microsoft.Web/sites/web") }
        assert_match "and this connection reaches #{SUBSCRIPTION}", error.message
      end

      test "the subscription goes on the map with the hostnames its apps serve, and a list it cannot read takes nothing away" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.Sql/servers") }.raises(AzureApi::Forbidden, "Azure answered 403: AuthorizationFailed")

        snapshot = @pack.map_of(@row)

        storefront = snapshot.resources.find { |resource| resource.external_id == WEB_ID }
        assert_equal [ ResourceMap::KIND_SERVICE, "running", PORTAL + WEB_ID + "/overview" ],
                     [ storefront.kind, storefront.status, storefront.url ]
        assert_equal({ "type" => "App Service app", "resource_group" => "shop", "region" => "westeurope", "plan" => "shop-plan", "sku" => "PremiumV3" }, storefront.details)
        assert_equal %w[api.happy.westeurope.azurecontainerapps.io shop.example.com storefront.azurewebsites.net], snapshot.links.map { |link| link.from.last }.sort
        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds
        assert_match "Azure SQL databases could not be read", snapshot.gap_texts.first
      end

      test "apps' settings are read in memory, a Key Vault reference or a secret by name only, and each database reports its server's address" do
        sql_url = "Server=tcp:shop-sql.database.windows.net,1433;Initial Catalog=orders;User ID=app;Password=azure-sql-pw"
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.Sql/servers") }
                .returns(pages([ { "id" => "#{GROUP}/Microsoft.Sql/servers/shop-sql", "name" => "shop-sql",
                                   "properties" => { "fullyQualifiedDomainName" => "shop-sql.database.windows.net" } } ]))
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/flexibleServers") }.returns(pages([
          { "id" => PG_ID, "name" => "catalog", "location" => "westeurope", "properties" => { "state" => "Ready", "fullyQualifiedDomainName" => "catalog.postgres.database.azure.com" } }
        ]))
        AzureApi.any_instance.stubs(:post).with { |path, *| path == "#{WEB_ID}/config/appsettings/list" }
                .returns({ "properties" => { "REDIS_URL" => "@Microsoft.KeyVault(SecretUri=https://shop.vault.azure.net/secrets/redis)", "THEME" => "dark" } })
        AzureApi.any_instance.stubs(:post).with { |path, *| path == "#{WEB_ID}/config/connectionstrings/list" }
                .returns({ "properties" => { "Orders" => { "value" => sql_url, "type" => "SQLAzure" } } })
        api = APP.deep_dup
        api["properties"]["template"]["containers"].first["env"] = [ { "name" => "DATABASE_URL", "value" => "postgres://app:pg-pw@catalog.postgres.database.azure.com:6432/catalog" },
                                                                      { "name" => "SECRET_DATABASE_URL", "secretRef" => "db-url" } ]
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.App/containerApps") }.returns(pages([ api ]))

        snapshot = @pack.map_of(@row)

        uses = snapshot.uses.map { |found| [ found.from.last, found.variable, found.address? ] }.sort
        assert_equal [ [ APP_ID, "DATABASE_URL", true ], [ APP_ID, "SECRET_DATABASE_URL", false ], [ WEB_ID, "Orders", true ], [ WEB_ID, "REDIS_URL", false ] ], uses
        assert_equal [ [ PG_ID, 5432 ], [ PG_ID, 6432 ], [ SQL_ID, 1433 ] ], snapshot.endpoints.map { |found| [ found.resource.last, found.port ] }.sort
        assert_no_setting_values(snapshot, sql_url, "azure-sql-pw", "pg-pw", "shop.vault.azure.net", "dark", "shop-sql.database.windows.net",
                                 "catalog.postgres.database.azure.com")

        ResourceMap.record!(@row, snapshot)
        ResourceMap::Matcher.new(@workspace).run!
        matched = ResourceMap::Link.where(workspace: @workspace, origin: ResourceMap::ORIGIN_MATCHED).includes(:from_resource, :to_resource)
                                   .map { |link| [ link.from_resource.name, link.to_resource.name, link.variables ] }.sort
        assert_equal [ [ "api", "catalog", [ "DATABASE_URL" ] ], [ "storefront", "orders", [ "Orders" ] ] ], matched
        assert_no_setting_values(snapshot, sql_url, "azure-sql-pw", "pg-pw")
      end

      test "app settings Reader may not list are one gap, and the other apps are not asked" do
        AzureApi.any_instance.expects(:post).with { |path, *| path.end_with?("/config/appsettings/list") }.once
                .raises(AzureApi::Forbidden, "Azure answered 403: AuthorizationFailed")

        snapshot = @pack.map_of(@row)

        gap = snapshot.gaps.select(&:settings).sole
        assert_match "Reading them needs Microsoft.Web/sites/config/list/action, which the Reader role does not include", gap.text
        assert_match "A custom role holding only that action is optional", gap.text
        assert_empty gap.kinds
        assert snapshot.complete?
        assert_not snapshot.settings_complete?
      end

      test "a resource's tags are kept in its details for finding it by, and one with none leaves the key out" do
        resource = { "id" => PG_ID, "name" => "catalog", "location" => "westeurope", "tags" => { "team" => "payments", "env" => "prod" } }
        assert_equal({ "team" => "payments", "env" => "prod" }, @pack.send(:item, resource, Azure::TYPE_POSTGRES, "Ready")[:details][ResourceMap::TAGS])
        assert_not @pack.send(:item, resource.merge("tags" => {}), Azure::TYPE_POSTGRES, "Ready")[:details].key?(ResourceMap::TAGS)
      end

      test "an app list that could not be read holds back the hostnames apps serve, and a server still provisioning reads pending" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/Microsoft.App/containerApps") }.raises(AzureApi::Forbidden, "Azure answered 403: AuthorizationFailed")

        snapshot = @pack.map_of(@row)

        assert_equal [ ResourceMap::KIND_SERVICE, ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
        assert_equal "pending", Integrations::Providers::Azure.status_of("Provisioning")
      end

      test "a list cut short is a gap with its kind unread, and Azure's states read as the map's words" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path.end_with?("/flexibleServers") }.returns(pages([
          { "id" => PG_ID, "name" => "catalog", "location" => "westeurope", "properties" => { "state" => "Updating" } }
        ], complete: false))

        snapshot = @pack.map_of(@row)

        assert_includes snapshot.gap_texts, "Only the first 1 PostgreSQL flexible servers were read."
        assert_equal [ ResourceMap::KIND_DATABASE ], snapshot.unread_kinds
        statuses = snapshot.resources.select { |resource| [ PG_ID, SQL_ID ].include?(resource.external_id) }.map(&:status)
        assert_equal %w[online updating], statuses.sort
        assert_equal %w[pending running], statuses.map { |status| Integrations::Providers::Azure.status_of(status) }.sort
      end

      test "a week of readings becomes a baseline per metric" do
        resource = ResourceMap::Resource.create!(workspace: @workspace, provider: "azure", account: SUBSCRIPTION, kind: ResourceMap::KIND_DATABASE, external_id: PG_ID,
                                                 name: "catalog", details: { "type" => Azure::TYPE_POSTGRES }, integration_environment: @row,
                                                 first_seen_at: Time.current, last_seen_at: Time.current)
        AzureApi.any_instance.stubs(:metrics).returns({ "value" => [ { "timeseries" => [ { "data" => [ { "timeStamp" => "2026-10-03T10:00:00Z", "average" => 37.0 } ] } ] } ] })

        found = @pack.baselines_of(@row, [ resource ], 7.days.ago..Time.current)

        assert_equal %w[cpu memory disk tcp_connections], found.map(&:metric)
        assert_equal [ "%", 37.0 ], [ found.first.unit, found.first.points.first.last ]
      end

      test "the health check reads the subscription" do
        AzureApi.any_instance.stubs(:subscription_details).raises(AzureApi::Error, "Azure answered 404: SubscriptionNotFound")

        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      test "an activity log event reads the one app or database it names again, with its hostnames, settings and address" do
        AzureApi.any_instance.expects(:list).never
        AzureApi.any_instance.stubs(:post).with { |path, *| path.end_with?("/config/appsettings/list") }.returns({ "properties" => { "DATABASE_URL" => "postgres://u:p@catalog.postgres.database.azure.com/shop" } })

        snapshot = @pack.map_refresh(@row, ResourceMap::Scope.new(account: SUBSCRIPTION, kind: ResourceMap::KIND_SERVICE, external_id: WEB_ID))

        assert_equal %w[shop.example.com storefront storefront.azurewebsites.net], snapshot.resources.map(&:name).sort
        assert_equal [ "DATABASE_URL" ], snapshot.uses.map(&:variable)

        AzureApi.any_instance.stubs(:get).with("#{GROUP}/Microsoft.Sql/servers/shop-sql", Azure::SQL_VERSION).returns(
          "name" => "shop-sql", "properties" => { "fullyQualifiedDomainName" => "shop-sql.database.windows.net" }
        )
        database = @pack.map_refresh(@row, ResourceMap::Scope.new(account: SUBSCRIPTION, kind: ResourceMap::KIND_DATABASE, external_id: SQL_ID))
        assert_equal [ "orders", "shop-sql" ], [ database.resources.sole.name, database.resources.sole.details["server"] ]
        assert_equal [ [ database.resources.sole.key, 1433 ] ], database.endpoints.map { |endpoint| [ endpoint.resource, endpoint.port ] }
      end

      test "an app Resource Manager answers not found for is gone, and one in another subscription is left to the sweep" do
        AzureApi.any_instance.stubs(:get).with(APP_ID, Azure::APP_VERSION).raises(AzureApi::NotFound, "Azure answered 404: ResourceNotFound")

        assert_equal [ [ "azure", SUBSCRIPTION, ResourceMap::KIND_SERVICE, APP_ID ] ],
                     @pack.map_refresh(@row, ResourceMap::Scope.new(account: SUBSCRIPTION, kind: ResourceMap::KIND_SERVICE, external_id: APP_ID)).gone
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.new(kind: ResourceMap::KIND_SERVICE, external_id: APP_ID.sub(SUBSCRIPTION, "99999999-2222-3333-4444-555555555555")))
        assert_nil @pack.map_refresh(@row, ResourceMap::Scope.everything)
      end

      private

      def pages(items, complete: true) = Integrations::Pages::Read.new(items: items, complete: complete)

      def table(columns, rows) = { "tables" => [ { "name" => "PrimaryResult", "columns" => columns.map { |name| { "name" => name } }, "rows" => rows } ] }

      def call(tool, arguments = {})
        Azure.new(@integration).call(tool.to_s, environment_row: @row, arguments: arguments)["content"].map { |part| part["text"] }.join("\n")
      end
    end
  end
end
