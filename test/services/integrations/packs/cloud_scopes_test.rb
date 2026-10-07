require "test_helper"
require Rails.root.join("db/migrate/20261007210300_keep_google_cloud_projects_and_azure_subscriptions_as_lists")

module Integrations
  module Packs
    # One Google Cloud connection reading several projects, and one Azure connection reading several subscriptions.
    class CloudScopesTest < ActiveSupport::TestCase
      ALL = IntegrationProvider::ConnectField::ALL
      KEY = { "type" => "service_account", "client_email" => "firefight@acme.iam.gserviceaccount.com", "private_key" => "pem" }.to_json
      PROD = "11111111-2222-3333-4444-555555555555".freeze
      STAGING = "99999999-2222-3333-4444-555555555555".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @gcp = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "GCP")
        @gcp_row = @gcp.integration_environments.create!
        GoogleCloud.store_credentials!(@gcp_row, GoogleCloud::KEY => KEY)
        @gcp_row.store_fields!(GoogleCloud::PROJECT => %w[acme-prod acme-staging])
        GoogleCloudApi.any_instance.stubs(:projects).returns(pages([
          { "projectId" => "acme-prod", "displayName" => "Acme prod", "state" => "ACTIVE" },
          { "projectId" => "acme-staging", "displayName" => "Acme staging", "state" => "ACTIVE" },
          { "projectId" => "acme-old", "displayName" => "Acme old", "state" => "DELETE_REQUESTED" }
        ]))
        %w[acme-prod acme-staging acme-new].each { |project| gcp_project(project) }

        @azure = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure")
        @azure_row = @azure.integration_environments.create!
        Azure.store_credentials!(@azure_row, Azure::SECRET => "s3cret")
        @azure_row.store_fields!(Azure::TENANT => "contoso.onmicrosoft.com", Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                                 Azure::SUBSCRIPTION => [ PROD, STAGING ])
        AzureApi.any_instance.stubs(:subscriptions).returns(pages([
          { "subscriptionId" => PROD, "displayName" => "Production", "state" => "Enabled" },
          { "subscriptionId" => STAGING, "displayName" => "Staging", "state" => "Enabled" },
          { "subscriptionId" => "33333333-2222-3333-4444-555555555555", "displayName" => "Closed", "state" => "Disabled" }
        ]))
        AzureApi.any_instance.stubs(:list).returns(pages([]))
        [ PROD, STAGING ].each do |subscription|
          AzureApi.any_instance.stubs(:list).with { |path, *| path == "/subscriptions/#{subscription}/providers/Microsoft.Web/sites" }
                  .returns(pages([ site(subscription) ]))
        end
        AzureApi.any_instance.stubs(:post).returns({ "properties" => {} })
      end

      test "two Google Cloud projects' services called web stay apart, each named with its project" do
        webs = GoogleCloud.new(@gcp).map_of(@gcp_row).resources.select { |found| found.name == "web" }

        assert_equal %w[acme-prod acme-staging], webs.map(&:account)
        assert_equal [ [ "acme-prod", "Acme prod" ], [ "acme-staging", "Acme staging" ] ], webs.map { |found| found.details.values_at(ResourceMap::SCOPE, ResourceMap::SCOPE_NAME) }
      end

      test "every Google Cloud project the key can read is listed at each sweep, leaving out one waiting to be deleted" do
        @gcp_row.store_fields!(GoogleCloud::PROJECT => [ ALL ])
        assert_equal %w[acme-prod acme-staging], GoogleCloud.new(@gcp).map_of(@gcp_row).resources.filter_map { |found| found.details[ResourceMap::SCOPE] }.uniq

        GoogleCloudApi.any_instance.stubs(:projects).returns(pages([ { "projectId" => "acme-prod", "state" => "ACTIVE" }, { "projectId" => "acme-new", "state" => "ACTIVE" } ]))
        assert_equal %w[acme-prod acme-new], GoogleCloud.new(@gcp).map_of(@gcp_row.reload).resources.filter_map { |found| found.details[ResourceMap::SCOPE] }.uniq
      end

      test "a Google Cloud call finds its project from the resource on the map, refuses a name two projects hold, and a change stays in its project" do
        tool = tool!(@gcp, GoogleCloud, "scale_service")
        mapped(@gcp_row, "google_cloud", "acme-staging", "projects/acme-staging/locations/us-central1/services/web")
        GoogleCloudApi.any_instance.expects(:update_run_service).with { |project, *| project == "acme-staging" }.returns({})

        NativeExecutor.call(tool: tool, environment_row: @gcp_row, arguments: { "resource" => "web", "min_instances" => 2 })

        mapped(@gcp_row, "google_cloud", "acme-prod", "projects/acme-prod/locations/us-central1/services/web")
        error = assert_raises(Scopes::Unresolved) { NativeExecutor.call(tool: tool, environment_row: @gcp_row, arguments: { "resource" => "web", "min_instances" => 2 }) }
        assert_match "is in more than one project GCP (Google Cloud) reaches: acme-prod and acme-staging", error.message
      end

      test "Azure subscriptions go on the map apart, and a subscription the principal cannot read is a gap while the other is read" do
        AzureApi.any_instance.stubs(:list).with { |path, *| path == "/subscriptions/#{STAGING}/providers/Microsoft.Web/sites" }
                .raises(AzureApi::Forbidden, "Azure answered 403: AuthorizationFailed")

        snapshot = Azure.new(@azure).map_of(@azure_row)

        assert_equal [ PROD ], snapshot.resources.select { |found| found.name == "storefront" }.map(&:account)
        assert_equal [ "Production" ], snapshot.resources.filter_map { |found| found.details[ResourceMap::SCOPE_NAME] }.uniq
        assert_match "App Service and Function apps could not be read", snapshot.gap_texts.join
        assert_not snapshot.complete?
      end

      test "every Azure subscription the principal can read leaves out a disabled one, and the form lists them" do
        options = Azure.scope_options({ Azure::SECRET => "s3cret" }, fields: { Azure::TENANT => "contoso.onmicrosoft.com", Azure::CLIENT => "22222222-2222-3333-4444-555555555555" })

        assert_equal [ [ PROD, "Production" ], [ STAGING, "Staging" ] ], options.map { |option| [ option.value, option.label ] }
        @azure_row.store_fields!(Azure::TENANT => "contoso.onmicrosoft.com", Azure::CLIENT => "22222222-2222-3333-4444-555555555555", Azure::SUBSCRIPTION => [ ALL ])
        assert_equal [ PROD, STAGING ], ConnectionSettings.of(@azure_row).scopes
      end

      test "an Azure restart reaches the subscription its resource lives in, and the confirmation names it" do
        tool!(@azure, Azure, "restart_resource")
        resource = mapped(@azure_row, "azure", STAGING, "/subscriptions/#{STAGING}/resourceGroups/shop/providers/Microsoft.Web/sites/storefront", type: "App Service app")

        call = Capabilities.resolve(@workspace, Capabilities::RESTART, { "resource" => resource.id }, principal: workspace_memberships(:alice_workspace_one))

        assert_equal STAGING, call.arguments[Azure::SUBSCRIPTION]
        label = @azure.target_label(@azure_row, scope: STAGING)
        assert label.end_with?("subscription #{STAGING}")
        assert_not_includes label, PROD
      end

      test "a project or subscription kept as one string becomes a list of it, and back" do
        @gcp_row.store_fields!(GoogleCloud::PROJECT => "acme-prod")
        @azure_row.store_fields!(Azure::TENANT => "contoso.onmicrosoft.com", Azure::SUBSCRIPTION => PROD)

        migrate(:up)
        assert_equal [ "acme-prod" ], @gcp_row.reload.fields[GoogleCloud::PROJECT]
        assert_equal({ Azure::TENANT => "contoso.onmicrosoft.com", Azure::SUBSCRIPTION => [ PROD ] }, @azure_row.reload.fields)

        migrate(:down)
        assert_equal "acme-prod", @gcp_row.reload.fields[GoogleCloud::PROJECT]
        assert_equal PROD, @azure_row.reload.fields[Azure::SUBSCRIPTION]
      end

      private

      def pages(items) = Integrations::Pages::Read.new(items: items, complete: true)

      def gcp_project(project)
        id = "projects/#{project}/locations/us-central1/services/web"
        GoogleCloudApi.any_instance.stubs(:run_locations).with(project).returns(pages([ { "locationId" => "us-central1" } ]))
        GoogleCloudApi.any_instance.stubs(:run_services).with(project, "us-central1").returns(pages([
          { "name" => id, "uri" => "https://web-#{project}.a.run.app", "terminalCondition" => { "type" => "Ready", "state" => "CONDITION_SUCCEEDED" } }
        ]))
        GoogleCloudApi.any_instance.stubs(:run_service).with(project, "us-central1", "web").returns(
          "name" => id, "etag" => "e1", "template" => { "containers" => [ {} ] }, "scaling" => {}
        )
        GoogleCloudApi.any_instance.stubs(:sql_instances).with(project).returns(pages([]))
        GoogleCloudApi.any_instance.stubs(:compute_instances).with(project).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
        GoogleCloudApi.any_instance.stubs(:clusters).with(project).returns(GoogleCloudApi::Reached.new(items: [], complete: true, unreachable: []))
      end

      def site(subscription)
        { "id" => "/subscriptions/#{subscription}/resourceGroups/shop/providers/Microsoft.Web/sites/storefront", "name" => "storefront", "kind" => "app",
          "location" => "westeurope", "properties" => { "state" => "Running", "enabledHostNames" => [] } }
      end

      def tool!(integration, pack, name)
        definition = pack.tool_definitions.find { |each| each.name == name }
        integration.tools.create!(name: name, params_schema: definition.params_schema, read_only: definition.read_only, enabled: true)
      end

      def mapped(row, provider, scope, id, type: nil)
        ResourceMap::Resource.create!(workspace: @workspace, integration_environment: row, provider: provider, account: scope, kind: ResourceMap::KIND_SERVICE,
                                      external_id: id, name: id.split("/").last, details: { ResourceMap::SCOPE => scope, "type" => type }.compact,
                                      first_seen_at: Time.current, last_seen_at: Time.current)
      end

      def migrate(direction) = ActiveRecord::Migration.suppress_messages { KeepGoogleCloudProjectsAndAzureSubscriptionsAsLists.new.migrate(direction) }
    end
  end
end
