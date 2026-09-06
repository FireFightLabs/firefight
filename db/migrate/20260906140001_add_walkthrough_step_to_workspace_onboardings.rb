# Last coaching step posted, so a step is never posted twice.
class AddWalkthroughStepToWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_onboardings, :walkthrough_step, :integer
  end
end
