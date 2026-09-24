class KeepWhatARunWasTold < ActiveRecord::Migration[8.1]
  def change
    add_column :investigations, :brief, :jsonb, default: {}, null: false
  end
end
