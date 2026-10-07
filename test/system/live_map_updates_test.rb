require "application_system_test_case"

class LiveMapUpdatesTest < ApplicationSystemTestCase
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    # Northflank stands in for a provider set up by hand, with the test provider's changes.
    Integrations::Providers::Northflank.stubs(:map_events).returns(LiveTestEvents)
    @row = connect_live!(@workspace, provider: "northflank", name: "Northflank")
    @row.give_map_events_token!
    @previous_host = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
  end

  teardown do
    ENV["APP_HOST"] = @previous_host
  end

  test "an admin sends a provider's changes to the connection's address and saves its secret, and the map says live updates are on" do
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => @row.integration_id)

    assert_text "Live updates: off"
    assert_text "Send Northflank's changes to Firefight and save the signing secret under Integrations to turn them on."
    assert_text "/api/v1/map_events/#{@row.map_events_token}"
    assert_text LiveTestEvents.setup_steps.first
    page.scroll_to(find("#map-events-secret-#{@row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-setup.png"))

    fill_in "map-events-secret-#{@row.id}", with: "whsec"
    click_button "Save secret"

    assert_text "Signing secret saved. Changes Northflank sends now reach the map."
    assert_text "Live updates: on, no change received yet"
    assert_equal "whsec", @row.reload.map_events_secret
    page.scroll_to(find("#map-events-secret-#{@row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-saved.png"))

    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ LiveTestPack.found(ResourceMap::KIND_SERVICE, "web") ]))
    @row.update!(map_events_received_at: 3.minutes.ago)
    visit resource_map_path

    within("aside[aria-label='What needs attention']") do
      assert_text "Live updates"
      assert_text "Live updates: on, last event 3 minutes ago"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-map.png"))
  end

  test "a connection Firefight registered for changes says live updates are on, and one whose plan refused says why it is off" do
    render = connect_live!(@workspace, provider: "render", name: "Render")
    render.give_map_events_token!
    render.update!(map_events_webhook_id: "whk-1", map_events_secret: "whsec_c2VjcmV0", map_events_received_at: 3.minutes.ago)
    vercel = connect_live!(@workspace, provider: "vercel", name: "Vercel")
    vercel.update!(map_events_error: "Vercel answered 403: Webhooks are not available on the Hobby plan. #{Integrations::MapEventSources::Vercel::PLAN_NOTE}")

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => render.integration_id)
    assert_text "Live updates: on, last event 3 minutes ago"
    assert_no_selector "#map-events-secret-#{render.id}"
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-render.png"))

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => vercel.integration_id)
    assert_text "Live updates: off"
    assert_text "Firefight could not follow Vercel's changes: Vercel answered 403: Webhooks are not available on the Hobby plan."
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-vercel-refused.png"))
  end

  test "a Render workspace where Firefight's webhook would be the only one waits for an admin to turn live updates on, and off again" do
    render = connect_live!(@workspace, provider: "render", name: "Render")
    Integrations::Packs::Render.store_credentials!(render, Integrations::Packs::Render::API_KEY => "rnd_key")
    render.store_fields!(Integrations::Packs::Render::WORKSPACE => "tea-1")
    Integrations::RenderApi.any_instance.stubs(:webhooks).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::RenderApi.any_instance.stubs(:create_webhook).returns("id" => "whk-1", "secret" => "whsec_c2VjcmV0")
    Integrations::RenderApi.any_instance.stubs(:delete_webhook).returns({})
    Integrations::MapEvents.prepare!(render)

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => render.integration_id)
    assert_text "Live updates: off"
    assert_text "Firefight asks before adding its webhook to Render."
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-render-turn-on.png"))

    click_button "Turn on"
    within(find("[role='dialog']", text: "Turn on live updates?")) do
      assert_text Integrations::MapEventSources::Render::ONLY_WEBHOOK
      page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-render-confirm.png"))
      click_button "Turn on"
    end
    # The toast is hidden from view until the dialog has closed.
    assert_no_selector "[role='dialog']", text: "Turn on live updates?"
    assert_text "Live updates are on. Changes Render sends now reach the map."
    assert_text "Live updates: on, no change received yet"
    assert_equal "whk-1", render.reload.map_events_webhook_id

    # A fresh page, so the turn on toast is gone before the turn off one shows.
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => render.integration_id)
    click_button "Turn off"
    within(find("[role='dialog']", text: "Turn off live updates?")) { click_button "Turn off" }
    # The toast is hidden from view until the dialog has closed.
    assert_no_selector "[role='dialog']", text: "Turn off live updates?"
    assert_text "Live updates are off. Firefight removed its webhook from Render."
    assert_text "Live updates were turned off, so the map updates at each sweep."
  end

  test "an admin adds each PlanetScale database's signing secret, and can forget them all to start over" do
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    row = planetscale.integration_environments.create!
    row.give_map_events_token!

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => planetscale.id)
    assert_text "Live updates: off"
    assert_text Integrations::MapEventSources::Planetscale.setup_steps.first
    assert_button "Forget secrets", disabled: true
    page.scroll_to(find("#map-events-secret-#{row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-planetscale-setup.png"))

    fill_in "map-events-secret-#{row.id}", with: "first-database-secret"
    click_button "Add secret"
    assert_text "Signing secret added. PlanetScale now has 1 signing secret saved, and a change signed with any one reaches the map."
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => planetscale.id)
    fill_in "map-events-secret-#{row.id}", with: "second-database-secret"
    click_button "Add secret"
    assert_text "Signing secret added. PlanetScale now has 2 signing secrets saved, and a change signed with any one reaches the map."
    assert_text "Live updates: on, no change received yet"
    assert_selector "#map-events-secret-#{row.id}[placeholder='2 saved. Paste another to add it']"
    page.scroll_to(find("#map-events-secret-#{row.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-planetscale-saved.png"))

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => planetscale.id)
    click_button "Forget secrets"
    within(find("[role='dialog']", text: "Forget signing secrets?")) do
      assert_text "Firefight forgets the 2 signing secrets saved for PlanetScale."
      page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-planetscale-forget.png"))
      click_button "Forget secrets"
    end
    # The toast is hidden from view until the dialog has closed.
    assert_no_selector "[role='dialog']", text: "Forget signing secrets?"
    assert_text "Signing secrets forgotten. Changes PlanetScale sends no longer reach the map until you add a secret again."
    assert_text "Live updates: off"
    assert_empty row.reload.map_events_secrets
  end

  test "an AWS connection offers each region's stack to get changes instantly, and shows the region that sends them" do
    Integrations::AwsApi.any_instance.stubs(:identity).returns(account: "123456789012")
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    row = integration.integration_environments.create!
    row.store_fields!(Integrations::Packs::Aws::REGIONS => %w[eu-west-1 us-east-1])
    Integrations::MapEvents.prepare!(row)
    row.reload.map_events_sent!("eu-west-1")
    template = Integrations::MapEventSources::Aws::TEMPLATE_URL
    previous = ENV[template]
    ENV[template] = "https://firefight-templates.s3.us-east-1.amazonaws.com/aws-live-updates.json"

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)

    assert_text "Live updates: on"
    assert_text "Get changes instantly"
    assert_text "Sending, last heard from just now"
    assert_text "Not sending yet"
    link = find_link("Create stack")
    assert_equal "_blank", link[:target]
    assert_includes link[:href], "/live_updates_setup?environment_row_id=#{row.id}&place=us-east-1"
    assert_no_text row.map_events_secret
    assert_text "To stop, delete the CloudFormation stack #{Integrations::MapEventSources::Aws.stack_name(row)} in eu-west-1."
    page.scroll_to(find_link("Create stack"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/live-updates-aws.png"))
  ensure
    ENV[template] = previous if template
  end
end
