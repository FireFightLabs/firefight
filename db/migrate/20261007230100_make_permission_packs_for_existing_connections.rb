# Every connection gets its read, changes and everything packs, and each workspace with a connection gets Changes
# everywhere, filled with the tools already switched on. Tools keep their on or off choice. Safe to run again.
class MakePermissionPacksForExistingConnections < ActiveRecord::Migration[8.1]
  def up
    Ability::Role.reset_column_information
    Integration.where(deleted_at: nil).includes(:workspace).find_each { |integration| Ability::Role.keep_in_step!(integration) }
  end

  def down
    Ability::Role.reset_column_information
    Ability::Role.built_in.find_each(&:retire!)
  end
end
