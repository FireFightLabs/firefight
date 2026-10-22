require "application_system_test_case"

# The connection's Live updates section for the three ways a provider's changes reach Firefight beside or instead of a
# sweep: Cloudflare set up by hand with a secret Firefight makes and the page never holds, Convex turned on and off at a cost, and Azure, whose
# activity log is read either way while instant updates are turned on, refused and said apart.
class LiveUpdatesSheetTest < ApplicationSystemTestCase
  SHOTS = "tmp/screenshots/live-updates-ui".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @previous_host = ENV["APP_HOST"]
    ENV["APP_HOST"] = "firefight.example.com"
    FileUtils.mkdir_p(Rails.root.join(SHOTS))
  end

  teardown do
    ENV["APP_HOST"] = @previous_host
  end

  test "Cloudflare waits for its Pages notifications, makes the secret, copies it only on request, and says what a notification does" do
    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.example/mcp" })
    row = cloudflare.integration_environments.create!
    row.give_map_events_token!
    address = Integrations::MapEvents.url_for(row)

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => cloudflare.id)
    within(section) do
      assert_selector "[data-live-status]", exact_text: "On, checked every 5 minutes, no change received yet"
      assert_text "Pages notifications: waiting for setup"
      assert_text "Firefight's address"
      assert_selector "[data-map-events-address]", exact_text: address
      assert_text Integrations::MapEventSources::Cloudflare.setup_steps.first
      assert_text "It does not change the map"
    end
    shot("cloudflare-01-waiting", find("[data-map-events-address]"))
    find("button", text: "Copy").hover
    assert_selector "[role='tooltip']", text: "Copy Firefight's address"
    shot("cloudflare-02-copy-tooltip")

    click_button "Make signing secret"
    assert_toast "Cloudflare's signing secret was made. Copy it with Copy secret."
    within(section) do
      assert_text "Pages notifications: ready (secret saved)"
      assert_button "Replace signing secret"
    end
    secret = row.reload.map_events_secret
    assert_not_includes page.html, secret, "the page never holds the secret"
    shot("cloudflare-03-ready", find("button", text: "Copy secret"))

    allow_clipboard!
    click_button "Copy secret"
    assert_toast "Signing secret copied."
    assert_equal secret, page.evaluate_async_script("navigator.clipboard.readText().then(arguments[0])")
    shot("cloudflare-04-copied", find("button", text: "Copy secret"))

    click_button "Replace signing secret"
    within(find("[role='dialog']", text: "Replace the signing secret?")) do
      assert_text "The secret saved now stops working at once"
      shot("cloudflare-05-replace-confirm")
      click_button "Replace secret"
    end
    assert_toast "Cloudflare's signing secret was replaced. The old one stopped working, so give each webhook the new one. Copy it with Copy secret."
    assert_not_equal secret, row.reload.map_events_secret
    assert_not_includes page.html, row.map_events_secret
  end

  test "Convex says what turning on gains and costs, and turning off says the sweep takes over once" do
    convex = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "convex", name: "Convex", slug: "convex")
    row = convex.integration_environments.create!
    row.give_map_events_token!
    source = Integrations::MapEventSources::Convex
    source.stubs(:confirmation_for).returns(source::ONLY_STREAM)
    source.stubs(:register).returns(Integrations::MapEventSource::Webhook.new(id: "stream-1", secret: "hmac"))
    source.stubs(:remove).returns(nil)
    Integrations::MapEvents.prepare!(row, now: true)

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => convex.id)
    within(section) { assert_selector "[data-live-status]", exact_text: "Off" }
    shot("convex-01-off")

    click_button "Turn on live updates"
    within(find("[role='dialog']", text: "Turn on live updates?")) do
      assert_text "so a push, a pause or a settings change reaches Firefight within about a minute. Convex allows one webhook log stream per deployment"
      shot("convex-02-turn-on-confirm")
      click_button "Turn on"
    end
    assert_toast "Live updates are on. Changes Convex sends now reach the map."
    within(section) { assert_selector "[data-live-status]", exact_text: "On, no change received yet" }
    shot("convex-03-on")

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => convex.id)
    click_button "Turn off live updates"
    within(find("[role='dialog']", text: "Turn off live updates?")) do
      assert_text "Firefight removes its webhook log stream from this Convex deployment, so your team can add its own. Changes then reach the map at each hourly sweep."
      shot("convex-04-turn-off-confirm")
      click_button "Turn off"
    end
    assert_toast "Live updates are off. Firefight removed its webhook from Convex, and changes reach the map at each hourly sweep."
    within(section) do
      assert_selector "[data-live-status]", exact_text: "Off"
      assert_text "Changes reach the map at each hourly sweep until someone turns them on again."
      assert_no_text "Live updates were turned off"
    end
    shot("convex-05-off-again")
  end

  test "Azure keeps checking its activity log while instant updates are turned on, refused in plain words, and on" do
    azure = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    row = azure.integration_environments.create!
    row.store_fields!(Integrations::Packs::Azure::SUBSCRIPTION => "11111111-2222-3333-4444-555555555555")
    row.store_learned!(Integrations::ConnectionSettings::SCOPES_LEARNED => [ { "value" => "11111111-2222-3333-4444-555555555555", "label" => "Production" } ])
    source = Integrations::MapEventSources::Azure
    Integrations::MapEvents.prepare!(row, now: true)

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => azure.id)
    within(section) do
      assert_selector "[data-live-status]", exact_text: "On, checked every 5 minutes, no change received yet"
      assert_text "Instant updates: off"
    end
    shot("azure-01-before")

    click_button "Turn on instant updates"
    within(find("[role='dialog']", text: "Turn on instant updates?")) do
      assert_text "#{source.turn_on_words} #{source::CONFIRMATION}"
      assert_no_text "system topic"
      assert_no_text "service principal"
      shot("azure-02-turn-on-confirm")
    end
    refusal = format(source::NO_ROLE, role: source::GRID_ROLE, name: "Production")
    source.stubs(:register).raises(Integrations::Error, refusal)
    within(find("[role='dialog']", text: "Turn on instant updates?")) { click_button "Turn on" }
    assert_toast "Instant updates could not be turned on. #{refusal}"
    within(section) do
      assert_selector "[data-live-status]", exact_text: "On, checked every 5 minutes, no change received yet"
      assert_text "Instant updates could not be turned on"
      assert_text refusal
      assert_no_text "Azure answered"
    end
    shot("azure-03-refused")

    source.stubs(:register).returns(Integrations::MapEventSource::Webhook.new(id: { "s" => "/x" }.to_json, secret: "k", scopes: [ "s" ]))
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => azure.id)
    click_button "Turn on instant updates"
    within(find("[role='dialog']", text: "Turn on instant updates?")) { click_button "Turn on" }
    assert_toast "Instant updates are on. Changes Azure sends now reach the map."
    within(section) do
      assert_text "Instant updates: on"
      assert_button "Turn off instant updates"
      assert_no_text refusal
    end
    shot("azure-04-on")

    source.stubs(:remove).returns(nil)
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => azure.id)
    click_button "Turn off instant updates"
    within(find("[role='dialog']", text: "Turn off instant updates?")) do
      assert_text source.turn_off_words
      shot("azure-05-turn-off-confirm")
      click_button "Turn off"
    end
    assert_toast "Instant updates are off. Firefight removed its webhook from Azure and still checks for changes every 5 minutes."
    within(section) do
      assert_selector "[data-live-status]", exact_text: "On, checked every 5 minutes, no change received yet"
      assert_text "Instant updates: off"
    end
    shot("azure-06-off-again")
  end

  private

  # Headless Chrome refuses the clipboard until the page's origin is granted it.
  def allow_clipboard!
    origin = URI.join(page.current_url, "/").to_s.chomp("/")
    page.driver.browser.execute_cdp("Browser.grantPermissions", origin: origin, permissions: %w[clipboardReadWrite clipboardSanitizedWrite])
  end

  def section = page.document.find("[data-live-updates-section]")

  def shot(name, scroll_to = section)
    page.scroll_to(scroll_to, align: :center)
    page.save_screenshot(Rails.root.join(SHOTS, "#{name}.png"))
  end
end
