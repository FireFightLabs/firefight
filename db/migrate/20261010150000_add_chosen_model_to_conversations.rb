class AddChosenModelToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :chosen_model, :string
  end
end
