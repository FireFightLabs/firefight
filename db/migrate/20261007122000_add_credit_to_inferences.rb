class AddCreditToInferences < ActiveRecord::Migration[8.1]
  def change
    add_column :inferences, :max_output_tokens, :integer
    add_column :inferences, :error_kind, :string
    add_index :inferences, [ :error_kind, :created_at ], where: "error_kind IS NOT NULL"
    add_index :inferences, [ :provider, :status, :created_at ]
  end
end
