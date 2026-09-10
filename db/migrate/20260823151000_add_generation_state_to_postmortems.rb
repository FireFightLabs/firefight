# status doubled as the in-flight flag, so a hand-set in_progress looked like a running
# job and a failed job deleted the row.
class AddGenerationStateToPostmortems < ActiveRecord::Migration[8.1]
  def up
    add_column :postmortems, :generation_state, :string
    add_column :postmortems, :generation_error, :string

    execute <<~SQL
      UPDATE postmortems
      SET generation_state = 'generating', status = 'draft'
      WHERE status = 'in_progress' AND title LIKE 'Generating postmortem for %'
    SQL
  end

  def down
    execute "UPDATE postmortems SET status = 'in_progress' WHERE generation_state = 'generating'"
    remove_column :postmortems, :generation_error
    remove_column :postmortems, :generation_state
  end
end
