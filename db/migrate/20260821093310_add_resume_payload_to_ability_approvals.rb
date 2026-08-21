class AddResumePayloadToAbilityApprovals < ActiveRecord::Migration[8.1]
  def change
    add_column :ability_approvals, :resume_payload, :jsonb
  end
end
