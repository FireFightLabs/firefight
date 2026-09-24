# A rehearsal is a run nobody in the workspace sees, made to measure Halon, such as a replay of a finished run on another model
# or a bench run on a case whose cause is known. It never holds the incident's one live run.
class LetARunBeRehearsed < ActiveRecord::Migration[8.1]
  def change
    add_column :investigations, :rehearsal, :boolean, default: false, null: false
    add_reference :investigations, :replay_of, type: :uuid, foreign_key: { to_table: :investigations }, index: true
    add_column :investigations, :model_override, :string
    add_column :investigations, :provider_override, :string

    remove_index :investigations, [ :subject_type, :subject_id ], name: "index_investigations_on_live_subject",
                 unique: true, where: "status IN ('pending', 'running')"
    add_index :investigations, [ :subject_type, :subject_id ], name: "index_investigations_on_live_subject",
              unique: true, where: "status IN ('pending', 'running') AND rehearsal = false"
  end
end
