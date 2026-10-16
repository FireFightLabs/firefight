# Each generation names its attempt, so one that finishes after a newer attempt started is dropped, not saved.
class AddGenerationAttemptToPostmortems < ActiveRecord::Migration[8.1]
  def change
    add_column :postmortems, :generation_attempt, :uuid
  end
end
