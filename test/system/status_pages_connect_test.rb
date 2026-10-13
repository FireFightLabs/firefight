require "application_system_test_case"

class StatusPagesConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Statuspage and Instatus sit under Status pages and connect with an API key each" do
    Integrations::StatuspageApi.any_instance.stubs(:pages).returns(Integrations::Pages::Read.new(items: [ { "id" => "pg1", "name" => "Acme" } ], complete: true))
    Integrations::InstatusApi.any_instance.stubs(:pages).returns(Integrations::Pages::Read.new(items: [ { "id" => "pg2", "name" => "Acme" } ], complete: true))
    visit integrations_path

    tagline = find("p", text: "What your customers see about an incident or planned work")
    scroll_to(tagline, align: :top)
    within(tagline.find(:xpath, "../..")) do
      assert_text "Status pages"
      assert_text "Statuspage"
      assert_text "Instatus"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/status-pages-gallery.png"))

    { Integrations::Providers::Statuspage.key => [ "Statuspage", "It belongs to the organization rather than a person" ],
      Integrations::Providers::Instatus.key => [ "Instatus", "User settings, Developer settings" ] }.each do |key, (name, hint)|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)
      within("[role=dialog]") do
        assert_text "Connect #{name}"
        assert_text hint
        fill_in "API key", with: "#{key}-key"
        page.save_screenshot(Rails.root.join("tmp/screenshots/#{key}-connect.png"))
        click_button "Connect"
      end

      assert_toast "#{name} is connected."
      row = @workspace.integrations.find_by!(provider: key).integration_environments.sole
      assert_equal "#{key}-key", Integrations::ConnectionSettings.of(row).credential("api_key")
    end
  end

  test "a workflow's Status page update step offers the Statuspage and Instatus tools that change a page, and none that only read" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = Workflow.create!(workspace: @workspace, name: "Tell customers")
    tools = [ Integrations::Providers::Statuspage.key, Integrations::Providers::Instatus.key ].map do |key|
      integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: key, name: key.titleize)
      Integrations::DiscoveryService.sync!(integration)
      integration.tools
    end
    workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: workspace_memberships(:alice_workspace_one),
                   payload: { "step" => { "id" => "tell", "name" => "tell", "kind" => "status_page_update", "config" => {} } })
    visit workflow_path(workflow)

    find("[data-step='tell']").click
    find("button[role=combobox]", text: "Choose a tool").click

    tools.each do |found|
      assert_selector "[role=option]", text: found.find_by!(name: "post_incident_update").model_facing_name
      assert_selector "[role=option]", text: found.find_by!(name: "schedule_maintenance").model_facing_name
      assert_no_selector "[role=option]", text: found.find_by!(name: "list_incidents").model_facing_name
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/status-page-step-tools.png"))
  end
end
