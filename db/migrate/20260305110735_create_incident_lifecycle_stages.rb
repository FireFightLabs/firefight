class CreateIncidentLifecycleStages < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_lifecycle_stages, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :incident_lifecycle_stages, :key, unique: true
    add_index :incident_lifecycle_stages, :position

    add_reference :incident_statuses, :incident_lifecycle_stage, type: :uuid, null: true, foreign_key: true

    reversible do |dir|
      dir.up do
        triage = execute_insert("incident_lifecycle_stages", key: "triage", name: "Triage", description: "Potential incident under investigation, not yet confirmed as active.", position: 1)
        active = execute_insert("incident_lifecycle_stages", key: "active", name: "Active", description: "Confirmed incident actively being worked by responders.", position: 2)
        closed = execute_insert("incident_lifecycle_stages", key: "closed", name: "Closed", description: "Incident resolved and no longer actively managed.", position: 3)
        canceled = execute_insert("incident_lifecycle_stages", key: "canceled", name: "Canceled", description: "False positive, duplicate, or invalid incident. Excluded from resolved metrics.", position: 4)

        execute <<~SQL
          UPDATE incident_statuses SET incident_lifecycle_stage_id = '#{active}' WHERE category = 'live'
        SQL
        execute <<~SQL
          UPDATE incident_statuses SET incident_lifecycle_stage_id = '#{closed}' WHERE category = 'closed'
        SQL
      end
    end

    change_column_null :incident_statuses, :incident_lifecycle_stage_id, false
    remove_index :incident_statuses, [ :workspace_id, :category ]
    remove_column :incident_statuses, :category, :string, null: false
  end

  private

  def execute_insert(table, attrs)
    now = Time.current.utc.iso8601(6)
    id = SecureRandom.uuid
    columns = attrs.keys.map { |k| "\"#{k}\"" }.join(", ")
    values = attrs.values.map { |v| "'#{v}'" }.join(", ")
    execute <<~SQL
      INSERT INTO #{table} (id, #{columns}, created_at, updated_at) VALUES ('#{id}', #{values}, '#{now}', '#{now}')
    SQL
    id
  end
end
