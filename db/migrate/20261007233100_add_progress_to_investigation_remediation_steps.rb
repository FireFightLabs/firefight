# What a code change step's coding agent has done so far, shown on the run page while it works and summed up after.
class AddProgressToInvestigationRemediationSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_remediation_steps, :progress, :text
  end
end
