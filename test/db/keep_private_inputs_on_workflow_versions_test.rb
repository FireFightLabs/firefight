require "test_helper"
require Rails.root.join("db/migrate/20261013210000_keep_private_inputs_on_workflow_versions")

class KeepPrivateInputsOnWorkflowVersionsTest < ActiveSupport::TestCase
  NOTES = "Leave the billing replica alone, it is resized on Fridays.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
  end

  teardown do
    Workflow.reset_column_information
    Workflow::Version.reset_column_information
  end

  test "every version the workflow can go back to takes the workflow's private values, retired ones too" do
    workflow = workflow!("Probe")
    publish!(workflow)
    workflow.reload.open_draft!(by: @alice)
    publish!(workflow)
    workflow.reload.open_draft!(by: @alice)
    assert_equal [ Workflow::Version::STATUS_RETIRED, Workflow::Version::STATUS_LIVE, Workflow::Version::STATUS_DRAFT ], workflow.versions.order(:number).pluck(:status)
    keep_on_workflow!(workflow, raw_value(workflow.live_version))

    migrate(:up)

    workflow.versions.each { |version| assert_equal NOTES, version.reload.private_input_values["notes"], version.status }
  end

  test "rolling back a workflow with only a draft keeps the draft's private values" do
    workflow = workflow!("Draft only")
    sealed = raw_value(workflow.draft)

    migrate(:down)

    assert_equal sealed, raw_workflow_value(workflow)
  end

  test "rolling back keeps the live version's private values over the draft's" do
    workflow = workflow!("Live and draft")
    publish!(workflow)
    sealed = raw_value(workflow.reload.live_version)
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice, payload: { "trigger" => trigger(default: "Only shop.") })

    migrate(:down)

    assert_equal sealed, raw_workflow_value(workflow)
  end

  private

  def trigger(default: NOTES)
    { "kind" => "manual", "inputs" => [ { "key" => "notes", "question" => "What should Halon look at?", "default" => default, "private" => true } ] }
  end

  def workflow!(name)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    step = { "id" => "step_check", "name" => "check", "kind" => "run_skill", "config" => { "skill" => "probing_scan", "focus" => "{{inputs.notes}}" } }
    workflow.open_draft!(by: @alice).update!(trigger: trigger, steps: [ step ])
    workflow.reload
  end

  def publish!(workflow) = WorkflowPublishService.new(workflow.reload).publish!(workflow.draft, by: @alice)

  def raw_value(version) = select_raw("SELECT private_inputs FROM workflow_versions WHERE id = ?", version.id)

  def raw_workflow_value(workflow) = select_raw("SELECT private_inputs FROM workflows WHERE id = ?", workflow.id)

  def select_raw(sql, id) = Workflow.connection.select_value(Workflow.sanitize_sql_array([ sql, id ]))

  # The shape before the migration, the value on the workflow and none on its versions, rolled back with the test's
  # transaction.
  def keep_on_workflow!(workflow, sealed)
    connection = ActiveRecord::Base.lease_connection
    connection.remove_column :workflow_versions, :private_inputs
    connection.add_column :workflows, :private_inputs, :text
    connection.execute(Workflow.sanitize_sql_array([ "UPDATE workflows SET private_inputs = ? WHERE id = ?", sealed, workflow.id ]))
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { KeepPrivateInputsOnWorkflowVersions.new.migrate(direction) }
    Workflow.reset_column_information
    Workflow::Version.reset_column_information
  end
end
