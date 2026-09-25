# A chat question now does the work itself rather than handing it to an investigation, so each question may spend what
# a run may. Open conversations are moved to their workspace's run limits.
class GiveConversationsTheRunBudget < ActiveRecord::Migration[8.1]
  RUN_MAX_TURNS = 500
  RUN_MAX_SPEND_CENTS = 400

  def up
    execute <<~SQL
      UPDATE conversations
      SET max_turns = COALESCE(workspaces.investigation_max_turns, #{RUN_MAX_TURNS}),
          max_spend_cents = COALESCE(workspaces.investigation_max_spend_cents, #{RUN_MAX_SPEND_CENTS})
      FROM workspaces
      WHERE workspaces.id = conversations.workspace_id
    SQL
  end

  def down
    execute "UPDATE conversations SET max_turns = 40, max_spend_cents = 50"
  end
end
