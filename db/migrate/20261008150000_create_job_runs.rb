# A job that must not repeat a change notes when it starts and clears the note when it ends. A note still there when the
# same job starts again means its worker was stopped part way, by a deploy or a crash.
class CreateJobRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :job_runs, id: :uuid do |t|
      t.string :job_id, null: false
      t.string :job_class, null: false
      t.datetime :created_at, null: false
      t.index :job_id, unique: true
      t.index :created_at
    end
  end
end
