# Embedding the providers' documentation serves every workspace at once, so its calls are recorded with no workspace.
class AllowInferencesWithoutAWorkspace < ActiveRecord::Migration[8.1]
  def change
    change_column_null :inferences, :workspace_id, true
  end
end
