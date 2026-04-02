class CreateIncidentConditions < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_conditions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :conditionable, type: :uuid, null: false, polymorphic: true
      t.string :condition_field, null: false
      t.string :operator, null: false
      t.jsonb :values, null: false, default: []
      t.timestamps
    end

  end
end
