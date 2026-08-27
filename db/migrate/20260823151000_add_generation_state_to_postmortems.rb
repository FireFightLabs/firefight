# "status" doubled as the flag for an AI generation in flight, so a responder
# setting in_progress by hand looked like a running job and a failed job
# deleted the row. Generation now has its own column.
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
