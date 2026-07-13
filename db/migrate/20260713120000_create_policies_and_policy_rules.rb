class CreatePoliciesAndPolicyRules < ActiveRecord::Migration[8.1]
  def change
    create_table :policies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.string :domain, null: false
      t.string :name, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :domain_config, null: false, default: {}
      t.timestamps
    end
    add_index :policies, [ :workspace_id, :domain ]
    add_index :policies, [ :workspace_id, :domain, :name ], unique: true

    create_table :policy_rules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :policy, null: false, foreign_key: true, type: :uuid
      t.integer :priority, null: false
      t.jsonb :conditions, null: false, default: []
      t.jsonb :outcome, null: false, default: {}
      t.timestamps
    end
    add_index :policy_rules, [ :policy_id, :priority ], unique: true
  end
end
