require "application_system_test_case"

class AppHostsConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Railway asks for its token, then its project and environment, and keeps the ids as settings rather than secrets" do
    Integrations::RailwayApi.any_instance.stubs(:project).with("prj-1").returns(
      "id" => "prj-1", "environments" => { "edges" => [ { "node" => { "id" => "env-1", "name" => "production" } } ] }
    )
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => Integrations::Packs::Railway::PROVIDER_KEY)

    within("[role=dialog]") do
      assert_text "The id of the Railway project"
      fill_in "API token", with: "rw-token"
      fill_in "Project", with: "prj-1"
      fill_in "Environment", with: "staging"
      click_button "Connect"
      assert_text "The project has no environment called staging. It has production."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/railway-connect.png"))

    within("[role=dialog]") do
      fill_in "Environment", with: "production"
      click_button "Connect"
    end
    assert_text "Railway"
    row = @workspace.integrations.find_by!(provider: Integrations::Packs::Railway::PROVIDER_KEY).integration_environments.sole
    settings = Integrations::ConnectionSettings.of(row)
    assert_equal [ "prj-1", "production", "rw-token" ], [ settings.field("project"), settings.field("environment"), settings.credential("api_token") ]
    assert_nil row.credentials_hash["project"]
  end

  test "Render refuses a workspace that is not a workspace id, and Vercel's team may be left empty" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => Integrations::Packs::Render::PROVIDER_KEY)

    within("[role=dialog]") do
      fill_in "API key", with: "rnd_key"
      fill_in "Workspace", with: "my-team"
      click_button "Connect"
      assert_text "Workspace can hold only tea- followed by lowercase letters and numbers."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/render-connect.png"))

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => Integrations::Packs::Vercel::PROVIDER_KEY)
    within("[role=dialog]") do
      assert_text "Leave it empty for a personal account"
      assert_text "Team"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/vercel-connect.png"))
  end
end
