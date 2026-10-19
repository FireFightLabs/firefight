# Why a change Halon made in a chat ran without the person's yes, a safe change or an entry of the list of what Halon
# may do without asking. Kept on the call, the activity log row and the change's card.
class RecordWhyChangesRanWithoutAsking < ActiveRecord::Migration[8.1]
  def change
    %i[ability_invocations ruby_llm_tool_calls chat_mitigations].each do |table|
      add_column table, :unasked_reason, :string
      add_reference table, :allowance, type: :uuid, foreign_key: { to_table: :ability_allowances, on_delete: :nullify }
    end
  end
end
