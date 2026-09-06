# The last walkthrough step posted in the first test incident's channel, so a
# step is never posted twice and a skipped one is not posted late.
class AddWalkthroughStepToWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_onboardings, :walkthrough_step, :integer
  end
end
