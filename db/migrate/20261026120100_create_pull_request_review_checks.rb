# Each check a review ran on a finding before writing it, kept or dropped with why, on a chat of its own. A dropped
# finding is never shown, so this is the only place that says what the review thought and why it let it go.
class CreatePullRequestReviewChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_request_review_checks, id: :uuid do |t|
      t.references :pull_request_review, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :finding, type: :uuid, foreign_key: { to_table: :pull_request_review_findings, on_delete: :nullify }
      t.text :claim, null: false
      t.string :path
      t.string :verdict
      t.text :reason
      t.bigint :spent_micros, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :pull_request_review_checks, "verdict IS NULL OR verdict IN ('kept', 'dropped')", name: "pull_request_review_checks_verdict"
  end
end
