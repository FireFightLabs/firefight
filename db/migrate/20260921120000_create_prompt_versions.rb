# One row per distinct prompt wording, so a ledger row's version can be read back as the words the model was given.
class CreatePromptVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_versions, id: :uuid do |t|
      t.string :template, null: false
      t.string :version, null: false
      t.text :text, null: false
      t.datetime :first_seen_at, null: false
      t.timestamps
      t.index [ :template, :version ], unique: true
    end
  end
end
