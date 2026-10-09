class AddChangedAnswerToCodeAgentQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_questions, :changed_answer, :text
    add_column :code_agent_questions, :changed_chosen, :integer
    add_column :code_agent_questions, :changed_by_type, :string
    add_column :code_agent_questions, :changed_by_id, :uuid
    add_column :code_agent_questions, :changed_at, :datetime
    add_column :code_agent_questions, :correction_sent_for, :datetime
  end
end
