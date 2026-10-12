# A connection's read or changes pack can be held by every member without a grant, including members who join later.
# Members have always read every connected tool, so each read pack already made starts held by every member, and each
# changes pack starts held by nobody, as before.
class AddEveryMemberToAbilityRoles < ActiveRecord::Migration[8.1]
  def up
    add_column :ability_roles, :every_member, :boolean, default: false, null: false
    execute "UPDATE ability_roles SET every_member = TRUE WHERE pack = 'read' AND integration_id IS NOT NULL"
  end

  def down
    remove_column :ability_roles, :every_member
  end
end
