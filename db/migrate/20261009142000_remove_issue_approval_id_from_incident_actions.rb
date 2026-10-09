class RemoveIssueApprovalIdFromIncidentActions < ActiveRecord::Migration[8.1]
  def change
    remove_column :incident_actions, :issue_approval_id, :uuid
  end
end
