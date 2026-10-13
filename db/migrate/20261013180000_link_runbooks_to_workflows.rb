# A deleted workflow leaves each runbook that linked it a guide.
class LinkRunbooksToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_reference :runbooks, :workflow, type: :uuid, foreign_key: { on_delete: :nullify }, index: true
  end
end
