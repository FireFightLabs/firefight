class RenameInferenceCostCentsToMicros < ActiveRecord::Migration[8.1]
  def change
    rename_column :inferences, :cost_cents, :cost_micros
  end
end
