# Every kind of failure Halon looked at for a published version, so each is looked at once for that version however
# they take turns, and a newly published version starts with none.
class KeepRepairProblemsOnWorkflowVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :workflow_versions, :repair_problem_keys, :string, array: true, default: [], null: false
    remove_column :workflows, :repair_problem_key, :string
  end
end
