# Who answered a call Halon paused on, so its message can say who approved or cancelled it however often it is redrawn.
class AddDecidedByToRubyLlmToolCalls < ActiveRecord::Migration[8.1]
  def change
    add_reference :ruby_llm_tool_calls, :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
  end
end
