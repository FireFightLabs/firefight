class AddProvenanceToToolCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :ruby_llm_tool_calls, :provenance, :jsonb
  end
end
