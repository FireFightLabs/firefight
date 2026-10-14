require "test_helper"
require Rails.root.join("db/migrate/20261014800000_move_untouched_workflows_to_a_hundred_runs_an_hour")

class MoveUntouchedWorkflowsToAHundredRunsAnHourTest < ActiveSupport::TestCase
  test "a workflow still on the old default of 60 moves to 100, and one an admin set to anything else keeps it" do
    workspace = workspaces(:slack_workspace_one)
    untouched = Workflow.create!(workspace: workspace, name: "Untouched")
    set = Workflow.create!(workspace: workspace, name: "Set by hand")
    untouched.update_columns(runs_per_hour: 60)
    set.update_columns(runs_per_hour: 25)

    ActiveRecord::Migration.suppress_messages { MoveUntouchedWorkflowsToAHundredRunsAnHour.new.migrate(:up) }

    assert_equal [ 100, 25 ], [ untouched.reload.runs_per_hour, set.reload.runs_per_hour ]
  end
end
