# What an operator did to a sandbox or a kept copy from the console, and who.
class CreateOperatorSandboxActions < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_sandbox_actions, id: :uuid do |t|
      t.string :action, null: false
      t.string :provider, null: false
      t.string :kind, null: false
      t.string :ref, null: false
      t.string :operator, null: false
      t.text :outcome
      t.timestamps
    end
    add_index :operator_sandbox_actions, :created_at
  end
end
