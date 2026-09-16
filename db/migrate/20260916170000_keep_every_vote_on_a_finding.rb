class KeepEveryVoteOnAFinding < ActiveRecord::Migration[8.1]
  def change
    create_table :investigation_verdicts, id: :uuid do |t|
      t.references :finding, type: :uuid, null: false,
                   foreign_key: { to_table: :investigation_findings }, index: false
      t.references :member, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
      t.string :outcome, null: false
      t.timestamps
    end
    # One vote per person, changeable, so a tally is a count rather than a guess.
    add_index :investigation_verdicts, [ :finding_id, :member_id ], unique: true,
              name: "index_investigation_verdicts_on_finding_and_member"
  end
end
