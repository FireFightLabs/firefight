require "application_system_test_case"

class MapKeyChecksTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[query_metrics list_deployments].each do |name|
      integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    ]))
    @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    now = Time.current
    points = 24.times.map { |hour| [ now - hour.hours, 0.4 + ((hour % 4) * 0.05) ] }
    ResourceMap::Baseline.record!(@row, [ @web ], [ ResourceMap::Baseline::Found.new(key: @web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: points) ],
                                  window_from: now - 7.days, window_to: now)
  end

  test "a person opens a resource, sees its checks with their normal, and runs one inline through the gateway" do
    readings = 12.times.map { |minute| [ (Time.current - (12 - minute).minutes).utc.iso8601, minute < 9 ? 0.45 : 1.6 ] }
    chart = { "title" => "CPU of web", "unit" => "vCPU", "from" => 1.hour.ago.utc.iso8601, "to" => Time.current.utc.iso8601,
              "series" => [ { "label" => "web", "points" => readings } ] }
    Integrations::NativeExecutor.stubs(:call).returns(
      "content" => [ { "type" => "text", "text" => "web\nCPU of web (vCPU): min 0.45, avg 0.74, max 1.6, latest 1.6 (12 points)" } ],
      "structuredContent" => { "charts" => [ chart ] }
    )

    visit resource_map_path(ResourceMap::PAGE_VIEW_PARAM => "focus", ResourceMap::PAGE_RESOURCE_PARAM => @web.id)

    within("aside[aria-label='About web']") do
      assert_text(/key checks/i)
      assert_text "Read as 5xx responses from Northflank. No normal read yet"
      assert_text "From Northflank. Normal: usually 0.48 vCPU, 95% under 0.55 vCPU"
      assert_text "p95 latency"
      assert_text "Not available here"
      assert_text "Northflank does not keep latency_p95 for this resource."
      find("div", text: /\ACPU/, match: :first).find_button("Run").click
      assert_text "CPU of web, from Northflank. Now 1.6 vCPU, 2.9x the usual high of 0.55 vCPU (usually 0.48 vCPU)."
      assert_text "Run again"
      page.scroll_to(find("p", text: /2\.9x the usual high/), align: :center)
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/map-key-check-run.png"))
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.query_metrics", source: AbilityGateway::SOURCE_WEB)
  end
end
