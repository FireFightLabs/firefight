class RememberWhenAnAnswerIsOwed < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :answer_owed_since, :datetime
  end
end
