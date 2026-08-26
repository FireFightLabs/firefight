# An agent takes part in an incident as itself: it opens action items, claims
# them, links incidents and thanks people. Every column naming a participant
# has to hold a machine as readily as a person, which is what declared_by
# already does.
class MakeIncidentParticipantsPolymorphic < ActiveRecord::Migration[8.1]
  COLUMNS = {
    incident_actions: %i[created_by assignee],
    incident_action_updates: %i[created_by assignee],
    incident_relationships: %i[created_by],
    shoutouts: %i[from_member to_member]
  }.freeze

  # A polymorphic column cannot carry a foreign key, since the id it holds may
  # point at a membership, an agent, or a service key.
  FOREIGN_KEYS = {
    incident_actions: %i[created_by_id assignee_id],
    incident_action_updates: %i[created_by_id assignee_id],
    incident_relationships: %i[created_by_id],
    shoutouts: %i[from_member_id to_member_id]
  }.freeze

  def up
    COLUMNS.each do |table, names|
      names.each do |name|
        add_column table, :"#{name}_type", :string
        execute "UPDATE #{table} SET #{name}_type = 'WorkspaceMembership' WHERE #{name}_id IS NOT NULL"
      end
    end

    FOREIGN_KEYS.each do |table, columns|
      columns.each { |column| remove_foreign_key table, column: column }
    end

    add_index :incident_actions, [ :assignee_type, :assignee_id ]
  end

  def down
    remove_index :incident_actions, [ :assignee_type, :assignee_id ]

    FOREIGN_KEYS.each do |table, columns|
      columns.each { |column| add_foreign_key table, :workspace_memberships, column: column }
    end

    COLUMNS.each do |table, names|
      names.each { |name| remove_column table, :"#{name}_type" }
    end
  end
end
