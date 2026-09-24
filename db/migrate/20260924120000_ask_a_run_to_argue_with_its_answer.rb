class AskARunToArgueWithItsAnswer < ActiveRecord::Migration[8.1]
  def change
    add_column :investigations, :critique_asked_at, :datetime
  end
end
