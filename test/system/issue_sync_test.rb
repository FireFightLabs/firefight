require "application_system_test_case"

class IssueSyncTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    sign_in(users(:alice), @workspace)
    @linear = connect_tracker!(@workspace, provider: "linear", name: "Linear")
  end

  test "an admin chooses the tracker, when items get issues and where they go, then follows the webhook steps and saves the secret" do
    visit settings_workspace_path

    assert_text "Issue tracking"
    find("#issue-tracker").click
    find("[role=option]", text: "Linear").click
    find("#issue-creation").click
    find("[role=option]", text: "Always for follow-ups").click
    fill_in "Team", with: "ENG"
    assert_text "Save to see how to send this tracker's changes to Firefight."
    click_button "Save changes"

    assert_text "Workspace settings were updated."
    assert_text "In Linear, open Settings, then API, and choose New webhook."
    assert_text "Changes made in Linear do not reach Firefight until its webhook's signing secret is saved here."
    assert_text "/api/v1/issue_events/#{@workspace.reload.issue_webhook_token}"
    page.scroll_to(find("#issue-webhook-secret"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-setting-steps.png"))

    fill_in "issue-webhook-secret", with: "lin_wh_secret"
    click_button "Save changes"
    assert_no_text "do not reach Firefight until"
    page.scroll_to(find("#issue-webhook-secret"), align: :center)
    assert_equal [ "linear", Workspace::IssueSync::ISSUE_CREATION_FOLLOW_UPS, { "team" => "ENG" }, "lin_wh_secret" ],
                 [ @workspace.reload.issue_tracker, @workspace.issue_creation, @workspace.issue_tracker_target, @workspace.issue_webhook_secret ]
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-setting-saved.png"))
  end

  test "an item offers Create issue, shows why its issue is missing, and links its issue once it is there" do
    sync_with!(@workspace, @linear, creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    incident = incidents(:active_critical_ws1)
    asked = incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the database password")
    failed = incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Add a connection limit",
                                      issue_sync_state: IncidentAction::ISSUE_FAILED, issue_sync_note: "Linear refused to open the issue: Team ENG not found.")
    incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Fail over the primary",
                                      external_key: "ENG-12", external_url: "https://linear.app/acme/issue/ENG-12/fail-over", issue_integration: @linear,
                                      issue_sync_state: IncidentAction::ISSUE_LINKED,
                                      issue_sync_note: "Linear has nobody with the email bob@example.com, so the issue's assignee was left as it was.")

    visit incident_path(incident)

    within("#action-#{failed.id}") do
      assert_button "Try the issue again"
      assert_text "Linear refused to open the issue: Team ENG not found."
    end
    assert_equal "https://linear.app/acme/issue/ENG-12/fail-over", find_link("ENG-12")[:href]
    page.scroll_to(find("#action-#{failed.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-items.png"))

    within("#action-#{asked.id}") { click_button "Create issue" }
    within("#action-#{asked.id}") do
      assert_text "Firefight is opening its issue."
      assert_no_button "Create issue"
    end
    page.scroll_to(find("#action-#{asked.id}"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-item-opening.png"))

    tracker_answers("save_issue" => json_answer({ "id" => "ENG-30", "title" => "Rotate the database password",
                                                  "url" => "https://linear.app/acme/issue/ENG-30/rotate" }))
    stub_update_message
    perform_enqueued_jobs(only: IssueSyncJob)
    within("#action-#{asked.id}") do
      assert_link "ENG-30", href: "https://linear.app/acme/issue/ENG-30/rotate", wait: 10
      assert_no_text "Firefight is opening its issue."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-item-linked.png"))
  end

  test "an item is renamed in a dialog, let go of and reopened from its menu, each confirmed" do
    incident = incidents(:active_critical_ws1)
    item = incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the database password",
                                             assignee: @alice, status: IncidentAction::STATUS_IN_PROGRESS)
    visit incident_path(incident)

    row = find("#action-#{item.id}")
    row.hover
    row.find("button", text: "Item actions", visible: :all).click
    find("[role=menuitem]", text: "Rename").click
    within("[role=dialog]") do
      fill_in "Title", with: "Rotate every database password"
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-rename-dialog.png"))
      click_button "Rename"
    end
    assert_text "The item was renamed."
    assert_text "Rotate every database password"

    row = find("#action-#{item.id}")
    row.hover
    row.find("button", text: "Item actions", visible: :all).click
    find("[role=menuitem]", text: "Unassign").click
    assert_text "Nobody holds the item now."
    assert_nil item.reload.assignee

    item.update!(status: IncidentAction::STATUS_DONE)
    visit incident_path(incident)
    row = find("#action-#{item.id}")
    row.hover
    row.find("button", text: "Item actions", visible: :all).click
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-reopen-menu.png"))
    find("[role=menuitem]", text: "Reopen").click
    assert_text "The item was reopened."
    assert_equal IncidentAction::STATUS_OPEN, item.reload.status
  end

  test "a tracker connected with Firefight's app has its webhook registered, so the setting asks for nothing" do
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"], previous = "lin-app", ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"]
    app = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", slug: "linear_issue_sync", settings: {})
    app.integration_environments.create!
    IssueTrackerTestHelper::LINEAR_TOOLS.each { |tool| app.tools.create!(name: tool, description: tool, read_only: tool != "save_issue", enabled: false, params_schema: {}) }
    Integrations::Packs::Linear.any_instance.stubs(:register_issue_webhook).returns(Integrations::Issues::Webhook.new(id: "wh-1", secret: "s"))
    ENV["APP_HOST"], host = "ff.example.com", ENV["APP_HOST"]

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "linear")
    within("[role=dialog]") do
      assert_text "Connect for issue sync"
      assert_link "Connect the Linear app"
      page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-connect-app.png"))
    end

    visit settings_workspace_path
    find("#issue-tracker").click
    find("[role=option]", text: "Linear issue sync").click
    fill_in "Team", with: "ENG"
    click_button "Save changes"

    assert_text "Firefight registered the tracker's webhook itself"
    assert_no_field "issue-webhook-secret"
    assert_equal "wh-1", @workspace.reload.issue_webhook_id
    page.scroll_to(find("#issue-tracker"), align: :center)
    page.save_screenshot(Rails.root.join("tmp/screenshots/issue-sync-setting-registered.png"))
  ensure
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = previous
    ENV["APP_HOST"] = host
  end
end
