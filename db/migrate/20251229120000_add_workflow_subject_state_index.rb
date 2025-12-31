class AddWorkflowSubjectStateIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :workflows, [ :subject_type, :subject_id, :state ],
              name: "index_workflows_on_subject_and_state"
  end
end
