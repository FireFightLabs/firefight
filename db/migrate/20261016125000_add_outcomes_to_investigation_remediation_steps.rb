class AddOutcomesToInvestigationRemediationSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_remediation_steps, :already_done_reason, :string
    add_column :investigation_remediation_steps, :outcome_label, :string
    add_column :investigation_remediation_steps, :outcome_url, :string
    add_column :investigation_remediation_steps, :firefight_tool, :boolean, default: false, null: false
  end
end
