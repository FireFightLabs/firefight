class AddExpiresAtToAbilityGrants < ActiveRecord::Migration[8.1]
  def change
    add_column :ability_grants, :expires_at, :datetime
    add_index :ability_grants, :expires_at, where: "expires_at IS NOT NULL"
  end
end
