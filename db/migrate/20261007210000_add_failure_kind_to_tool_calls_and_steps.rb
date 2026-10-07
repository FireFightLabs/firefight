class AddFailureKindToToolCallsAndSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :ruby_llm_tool_calls, :failure_kind, :string
    add_column :investigation_steps, :failure_kind, :string
  end
end
