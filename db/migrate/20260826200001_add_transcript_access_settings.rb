# Reading an incident and reading every message said in its channel are
# different asks, so the transcript gets its own grantable resource. A grant
# alone is not enough: the workspace has to have turned access on, which is a
# decision an admin makes rather than one that arrives with a checkbox.
class AddTranscriptAccessSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :transcript_access_enabled, :boolean, default: false, null: false
    # Null keeps them forever, which a workspace can choose. The default is a
    # bounded window, since the milestones and the postmortem outlive it.
    add_column :workspaces, :transcript_retention_days, :integer, default: 30

    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(
      workspace_id: nil,
      key: Ability::Action::ACTIONS.map { |a| "#{Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS}.#{a}" }
    ).destroy_all
    remove_column :workspaces, :transcript_retention_days
    remove_column :workspaces, :transcript_access_enabled
  end
end
