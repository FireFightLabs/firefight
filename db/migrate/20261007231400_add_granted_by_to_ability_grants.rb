# Who made a grant, a person, an agent or a key, so a pack someone asked for names whoever gave it.
class AddGrantedByToAbilityGrants < ActiveRecord::Migration[8.1]
  def change
    add_reference :ability_grants, :granted_by, type: :uuid, polymorphic: true, index: false
  end
end
