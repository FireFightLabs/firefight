class AddProcedureToRunbooks < ActiveRecord::Migration[8.1]
  def change
    add_column :runbooks, :inputs, :jsonb, null: false, default: []
    add_column :runbooks, :aliases, :string, array: true, null: false, default: []
    add_column :runbooks, :watch, :jsonb
  end
end
