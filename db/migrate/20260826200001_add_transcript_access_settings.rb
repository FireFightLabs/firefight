# The transcript gets its own grantable resource, and a grant alone is not
# enough. The workspace has to have turned access on too.
class AddTranscriptAccessSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :transcript_access_enabled, :boolean, default: false, null: false
    add_column :workspaces, :transcript_retention_days, :integer, default: 30

    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(
      workspace_id: nil,
      key: Ability::Action::ACTIONS.map { |action| Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS, action) }
    ).destroy_all
    remove_column :workspaces, :transcript_retention_days
    remove_column :workspaces, :transcript_access_enabled
  end
end
