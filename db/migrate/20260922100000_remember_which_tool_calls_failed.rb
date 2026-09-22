class RememberWhichToolCallsFailed < ActiveRecord::Migration[8.1]
  # A tool that refused or errored still hands the model a result, so the row looked finished
  # and the page called it completed. The wrapper now says when the result was a failure.
  def change
    add_column :ruby_llm_tool_calls, :failed, :boolean, null: false, default: false
  end
end
