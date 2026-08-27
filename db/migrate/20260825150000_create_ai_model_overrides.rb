class CreateAiModelOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_model_overrides, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.string :purpose, null: false
      t.string :model, null: false
      t.string :provider
      t.timestamps
    end

    add_index :ai_model_overrides, [ :workspace_id, :purpose ], unique: true
  end
end
