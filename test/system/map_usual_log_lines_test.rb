require "application_system_test_case"

class MapUsualLogLinesTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @logs = integration.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web"),
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "api", name: "api")
    ]))
    @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    lines = 30.times.map { |index| "GET /orders/#{index} 200 in #{index * 3} ms" } + 12.times.map { |index| "user u#{index} signed in from 10.0.0.#{index}" } +
            4.times.map { |index| "ERROR payment provider timed out after #{3000 + index} ms" } + [ %(WARN slow query "SELECT * FROM orders" took 812 ms) ]
    ResourceMap::LogTemplate.record!(@row, @web, ResourceMap::LogMiner.mine(lines), at: 2.days.ago)
    ResourceMap::LogTemplate.record!(@row, @web, ResourceMap::LogMiner.mine(lines.first(20)), at: 1.day.ago)
  end

  test "a resource's panel shows the lines it usually logs, and one whose logs cannot be read says why" do
    visit resource_map_path(ResourceMap::PAGE_VIEW_PARAM => "focus", ResourceMap::PAGE_RESOURCE_PARAM => @web.id)

    within("aside[aria-label='About web']") do
      assert_text(/usual log lines/i)
      assert_text "GET /orders/<NUM> <NUM> in <NUM> ms"
      assert_text "ERROR payment provider timed out after <NUM> ms"
      assert_text "seen in 2 reads"
      assert_text "4 patterns are known from a week of its logs."
      page.scroll_to(find("code", text: "ERROR payment provider"), align: :center)
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-usual-log-lines.png"))

    @logs.update!(enabled: false)
    api = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "api")
    visit resource_map_path(ResourceMap::PAGE_VIEW_PARAM => "focus", ResourceMap::PAGE_RESOURCE_PARAM => api.id)
    within("aside[aria-label='About api']") do
      assert_text "Its logs cannot be read, so its usual lines are not known. Northflank would answer this with its search_logs tool, which is switched off."
    end
  end
end
