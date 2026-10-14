require "application_system_test_case"

class HalonWorkflowsTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Investigation.stubs(:available_for?).returns(true)
    Investigation.stubs(:start_refusal).returns(nil)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    adapter = WorkspaceAdapter.for(@workspace).class.any_instance
    adapter.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
    adapter.stubs(:update_workflow_publish_request).returns({ success: true })
    adapter.stubs(:post_workflow_publish_answer_to_user).returns({})
    adapter.stubs(:post_workflow_all_clear).returns({})
    adapter.stubs(:post_workflow_failure).returns({})
  end

  def drafted(name = "Look around", by: @alice, steps: nil)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: by)
    workflow.open_draft!(by: by).update!(
      steps: steps || [ { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => {} } } ],
      trigger: { "kind" => "manual", "inputs" => [ { "key" => "query", "question" => "What to look for?", "default" => "db" } ] }
    )
    workflow
  end

  def published(name = "Look around", **options)
    workflow = drafted(name, **options)
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    workflow.reload
  end

  test "the Workflows page lists workflows under Halon, and a draft is made from the library" do
    published
    sign_in(users(:alice), @workspace)
    visit halon_monitoring_path
    click_link "Workflows"

    assert_text "Look around"
    assert_text "By hand"

    click_button "New from the library"
    find("[role='menuitem']", text: "Look for probing in the logs").click
    assert_text "Days"
    click_button "Make draft"

    assert_toast "Look for probing in the logs was made as a draft."
    assert_text "Every weekday at 09:00"
  end

  test "a member whose making of workflows an admin took away is not offered a new one from the library" do
    published
    sign_in(users(:bob), @workspace)
    visit halon_workflows_path
    assert_text "Look around"
    assert_button "New from the library"

    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, action: Ability::Action.system!(Workflow::CREATE_KEY))
    visit halon_workflows_path

    assert_text "Look around"
    assert_no_button "New from the library"
  end

  test "without the workflows flag the nav item is not there" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    sign_in(users(:alice), @workspace)
    visit halon_monitoring_path

    assert_text "Monitoring"
    assert_no_link "Workflows"
  end

  test "running by hand asks the trigger's questions, says so and opens the run, which can be pinned" do
    workflow = published
    sign_in(users(:alice), @workspace)
    visit workflow_path(workflow)

    click_button "Run"
    fill_in "What to look for?", with: "api"
    perform_enqueued_jobs { within("[role='dialog']") { click_button "Run" } }
    assert_toast "Look around is running."
    assert_text "Run of"
    run = workflow.runs.sole
    assert_equal({ "query" => "api" }, run.inputs)

    find("#pin-run").click
    assert_toast "This run is pinned, so it keeps its details."
    assert run.reload.pinned?
    find("#pin-run").click
    assert_toast "This run is no longer pinned."
    assert_not run.reload.pinned?
  end

  test "publishing says what it grants, and a member asks an admin instead" do
    workflow = drafted
    sign_in(users(:alice), @workspace)
    visit workflow_path(workflow)

    click_button "Publish"
    assert_text "Publishing also lets it do the following"
    assert_text "Read incidents"
    within("[role='dialog']") { click_button "Publish" }
    assert_toast "Look around was published."
    assert workflow.reload.live?

    other = drafted("Members draft", by: @bob)
    sign_in(users(:bob), @workspace)
    visit workflow_path(other)
    click_button "Ask an admin to publish"
    assert_toast "to publish Members draft."
    assert_button "Asked an admin to publish", disabled: true
    assert other.publish_requests.waiting.exists?
  end

  test "settings save with a toast, and a workflow that never ran is deleted after a confirmation" do
    workflow = published
    sign_in(users(:alice), @workspace)
    visit workflow_path(workflow)
    find("[role=radio]", text: "Settings").click

    fill_in "Spending ceiling per run, in dollars", with: "2.50"
    fill_in "Most runs per hour", with: "12"
    click_button "Save settings"
    assert_toast "Look around was updated."
    assert_equal [ 250, 12 ], workflow.reload.values_at(:cost_cap_cents, :runs_per_hour)

    click_button "Delete"
    within("[role='dialog']") { click_button "Delete" }
    assert_toast "Look around was deleted."
    assert_nil Workflow.find_by(id: workflow.id)
  end

  test "a one off that ran is listed as done with its run and can be made to repeat" do
    sign_in(users(:alice), @workspace)
    workflow = drafted("Later check")
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow.draft.update!(trigger: { "kind" => "once_at", "at" => "2026-10-13T12:30", "time_zone" => "UTC", "inputs" => [] })
      WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
      travel 31.minutes
      perform_enqueued_jobs { WorkflowTriggerSweepJob.perform_now }
    end

    visit halon_workflows_path(tab: "done")
    assert_text "Later check"
    click_button "Repeat it"
    click_button "Make the draft"
    assert_toast "now has a draft that runs every weekday at 09:00"
  end

  test "the runs tab lists every run" do
    workflow = published
    perform_enqueued_jobs { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    sign_in(users(:alice), @workspace)

    visit halon_workflows_path(tab: "runs")

    assert_text "Look around"
    assert_text "Succeeded"
  end

  test "an admin sets how long runs keep their details" do
    sign_in(users(:alice), @workspace)
    visit settings_workspace_path

    fill_in "Keep run details for", with: "30"
    within(:xpath, "//form[.//input[@id='workflow-run-retention']]") { click_button "Save" }

    assert_toast "Workflow runs now keep their details for 30 days."
    assert_equal 30, @workspace.reload.workflow_run_retention_days
  end
end
