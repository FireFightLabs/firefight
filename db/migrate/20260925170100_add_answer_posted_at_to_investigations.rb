# When the answer, or why the run stopped, reached the thread, so a run that finished but never said so can be found.
class AddAnswerPostedAtToInvestigations < ActiveRecord::Migration[8.1]
  def up
    add_column :investigations, :answer_posted_at, :datetime
    # Nothing recorded delivery before, and nothing says these runs were not posted.
    execute <<~SQL.squish
      UPDATE investigations SET answer_posted_at = completed_at WHERE completed_at IS NOT NULL AND thread_id IS NOT NULL
    SQL
  end

  def down
    remove_column :investigations, :answer_posted_at
  end
end
