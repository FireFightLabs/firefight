# Why a person must look at a step's change before anyone merges it, such as an outside coding agent's pull request that
# touched a path the workspace keeps out of code changes.
class AddNeedsPersonToRemediationSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_remediation_steps, :needs_person, :text
  end
end
