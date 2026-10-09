class AddOptionsToCodeAgentQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_questions, :options, :text
    add_column :code_agent_questions, :recommended, :integer
    add_column :code_agent_questions, :recommended_reason, :text
    add_column :code_agent_questions, :chosen, :integer
  end
end
