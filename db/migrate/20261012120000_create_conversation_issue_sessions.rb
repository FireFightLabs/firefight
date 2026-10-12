# A chat someone started in a tracker's issue by assigning it to Firefight's app or mentioning it, and the session there
# Halon answers in. One session is one chat. asked_by is the Firefight member the tracker's person matched by email,
# whose chat list shows it, and nobody when they matched none.
class CreateConversationIssueSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_issue_sessions, id: :uuid do |t|
      t.references :conversation, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :asked_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.string :session_id, null: false
      t.string :issue_key
      t.string :issue_url
      t.timestamps
    end
    add_index :conversation_issue_sessions, [ :integration_id, :session_id ], unique: true, name: "index_conversation_issue_sessions_once"
  end
end
