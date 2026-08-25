class LetAgentsDecideApprovals < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :ability_approvals, :workspace_memberships, column: :approver_id, if_exists: true
    add_column :ability_approvals, :approver_type, :string
    add_column :ability_approvals, :agents_may_approve, :boolean, null: false, default: false

    execute <<~SQL
      UPDATE ability_approvals SET approver_type = 'WorkspaceMembership' WHERE approver_id IS NOT NULL
    SQL
    execute <<~SQL
      UPDATE ability_approvals
      SET approver_ids = (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('kind', 'user', 'id', value)), '[]'::jsonb)
        FROM jsonb_array_elements_text(approver_ids) AS value
      )
      WHERE jsonb_array_length(approver_ids) > 0 AND jsonb_typeof(approver_ids->0) = 'string'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE ability_approvals
      SET approver_ids = (
        SELECT COALESCE(jsonb_agg(element->>'id'), '[]'::jsonb)
        FROM jsonb_array_elements(approver_ids) AS element
        WHERE element->>'kind' = 'user'
      )
      WHERE jsonb_array_length(approver_ids) > 0
    SQL

    remove_column :ability_approvals, :agents_may_approve
    remove_column :ability_approvals, :approver_type
    add_foreign_key :ability_approvals, :workspace_memberships, column: :approver_id, if_not_exists: true
  end
end
