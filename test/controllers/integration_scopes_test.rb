require "test_helper"

# Choosing which projects a connection reads, on the connect form and again on the connection's details.
class IntegrationScopesTest < ActionDispatch::IntegrationTest
  PROJECTS = Integrations::Pages::Read.new(items: [ { "id" => "faylee", "name" => "Faylee" }, { "id" => "acme", "name" => "Acme" } ], complete: true)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    ApplicationController.any_instance.stubs(:current_user).returns(users(:alice))
    ApplicationController.any_instance.stubs(:current_workspace).returns(@workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
    Integrations::NorthflankApi.any_instance.stubs(:projects).returns(PROJECTS)
  end

  test "the connect form lists what a typed token can read, or says why it cannot" do
    post list_scopes_integrations_url, params: { provider: "northflank", credentials: { api_token: "nf" } }, as: :json

    assert_equal [ { "value" => "faylee", "label" => "Faylee" }, { "value" => "acme", "label" => "Acme" } ], response.parsed_body["options"]

    Integrations::NorthflankApi.any_instance.stubs(:projects).raises(Integrations::NorthflankApi::Error, "Northflank answered 401: Unauthorized")
    post list_scopes_integrations_url, params: { provider: "northflank", credentials: { api_token: "bad" } }, as: :json
    assert_equal "Northflank did not list this token's projects. Northflank answered 401: Unauthorized.", response.parsed_body["error"]
  end

  test "a connection made for every project the token can read keeps all, and its details offer the projects to choose again" do
    Integrations::ConnectionRefresh.stubs(:run!)

    post integrations_url, params: { provider: "northflank", name: "Faylee", credentials: { api_token: "nf" },
                                     fields: { project: [ IntegrationProvider::ConnectField::ALL ] } }

    row = @workspace.integrations.find_by!(name: "Faylee").integration_environments.sole
    assert Integrations::ConnectionSettings.of(row).all_scopes?
    get scope_options_integration_url(row.integration, environment_row_id: row.id), as: :json
    assert_equal %w[faylee acme], response.parsed_body["options"].pluck("value")
  end

  test "choosing projects again keeps them, reads the connection again and says so, and refuses one the token cannot read" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    row = integration.integration_environments.create!(credentials: { "api_token" => "nf" }.to_json)
    row.store_fields!("project" => %w[faylee])
    Integrations::ConnectionRefresh.expects(:run!).with(integration).once

    patch scopes_integration_url(integration), params: { environment_row_id: row.id, values: %w[faylee acme] }

    assert_equal "Faylee now reads projects Faylee and Acme.", flash[:notice]
    assert_equal %w[faylee acme], row.reload.fields["project"]

    patch scopes_integration_url(integration), params: { environment_row_id: row.id, values: %w[faylee elsewhere] }
    assert_equal "This token cannot read project elsewhere. Choose from what it lists.", flash[:alert]
    assert_equal %w[faylee acme], row.reload.fields["project"]

    patch scopes_integration_url(integration), params: { environment_row_id: row.id, values: [] }
    assert_equal "Choose at least one project, or all the token can read.", flash[:alert]
  end
end
