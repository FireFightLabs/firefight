class AddSelfApprovableToAbilityApprovals < ActiveRecord::Migration[8.1]
  def change
    add_column :ability_approvals, :self_approvable, :boolean, default: true, null: false
  end
end
