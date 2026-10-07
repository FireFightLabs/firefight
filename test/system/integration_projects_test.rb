require "application_system_test_case"

# One Northflank connection reading the projects a person picks from what the token lists, or all of them.
class IntegrationProjectsTest < ApplicationSystemTestCase
  PROJECTS = [ { "id" => "faylee", "name" => "Faylee" }, { "id" => "acme", "name" => "Acme" }, { "id" => "billing", "name" => "Billing" } ].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    Integrations::NorthflankApi.any_instance.stubs(:projects).returns(Integrations::Pages::Read.new(items: PROJECTS, complete: true))
    Integrations::NorthflankApi.any_instance.stubs(:project).returns({})
    Integrations::MapSweepJob.stubs(:perform_later)
  end

  test "the connect dialog lists the token's projects, takes several, and the connection lists them and chooses again with a toast" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "northflank")
    within("[role=dialog]") do
      fill_in "Connection name", with: "Faylee"
      fill_in "API token", with: "nf-token"
      click_button "Choose projects"
    end
    assert_selector "[role=option]", text: IntegrationProvider::ConnectField::ALL_LABEL
    find("[role=option]", text: "Faylee").click
    find("[role=option]", text: "Acme").click
    find("body").send_keys(:escape)
    page.save_screenshot(Rails.root.join("tmp/screenshots/northflank-connect-projects.png"))
    within("[role=dialog]") { click_button "Connect" }

    assert_no_selector "[role=dialog]"
    row = @workspace.integrations.find_by!(name: "Faylee").integration_environments.sole
    assert_equal %w[faylee acme], row.fields["project"]

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => row.integration_id)
    assert_text "Projects"
    assert_text "Faylee"
    assert_text "Acme"
    page.save_screenshot(Rails.root.join("tmp/screenshots/northflank-connection-projects.png"))

    click_button "Add more..."
    assert_selector "[role=option]", text: "Billing"
    page.save_screenshot(Rails.root.join("tmp/screenshots/northflank-connection-project-list.png"))
    find("[role=option]", text: IntegrationProvider::ConnectField::ALL_LABEL).click
    find("body").send_keys(:escape)
    click_button "Save"

    assert_text "Faylee now reads every project the token can read."
    assert_equal [ IntegrationProvider::ConnectField::ALL ], row.reload.fields["project"]
    assert_no_text "could not list"
    page.save_screenshot(Rails.root.join("tmp/screenshots/northflank-connection-all-projects.png"))
  end
end
