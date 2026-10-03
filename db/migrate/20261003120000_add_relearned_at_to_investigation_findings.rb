class AddRelearnedAtToInvestigationFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_findings, :relearned_at, :datetime
  end
end
