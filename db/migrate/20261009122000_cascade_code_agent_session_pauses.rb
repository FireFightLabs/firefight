# A pause goes with its session and workspace, and outlives the chat it was offered in and the person who decided it.
class CascadeCodeAgentSessionPauses < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :code_agent_session_pauses, :code_agent_sessions, column: :session_id
    add_foreign_key :code_agent_session_pauses, :code_agent_sessions, column: :session_id, on_delete: :cascade
    remove_foreign_key :code_agent_session_pauses, :workspaces
    add_foreign_key :code_agent_session_pauses, :workspaces, on_delete: :cascade
    remove_foreign_key :code_agent_session_pauses, :conversations
    add_foreign_key :code_agent_session_pauses, :conversations, on_delete: :nullify
    remove_foreign_key :code_agent_session_pauses, :workspace_memberships, column: :decided_by_id
    add_foreign_key :code_agent_session_pauses, :workspace_memberships, column: :decided_by_id, on_delete: :nullify
  end
end
