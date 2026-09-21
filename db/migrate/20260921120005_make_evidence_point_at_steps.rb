class MakeEvidencePointAtSteps < ActiveRecord::Migration[8.1]
  # Evidence was free text the agent typed, so nothing could check it. A claim now cites the
  # steps it rests on, and a step carries the number it is cited by and what it was.
  def change
    add_column :investigation_steps, :position, :integer
    add_column :investigation_steps, :tool_name, :string
    add_column :investigation_steps, :label, :string
    add_index :investigation_steps, [ :investigation_id, :position ], unique: true, where: "position IS NOT NULL"

    create_table :investigation_evidence, id: :uuid do |t|
      t.references :finding, type: :uuid, null: false, foreign_key: { to_table: :investigation_findings }
      t.integer :position, null: false
      t.text :claim, null: false
      t.timestamps
    end

    # What a claim or a settled theory rests on. A step today, a file range or a pull request later,
    # which is what locator is for.
    create_table :investigation_citations, id: :uuid do |t|
      t.references :cited_by, type: :uuid, polymorphic: true, null: false
      t.references :source, type: :uuid, polymorphic: true, null: false
      t.jsonb :locator, null: false, default: {}
      t.timestamps
    end

    remove_column :investigation_findings, :evidence, :jsonb, null: false, default: []
  end
end
