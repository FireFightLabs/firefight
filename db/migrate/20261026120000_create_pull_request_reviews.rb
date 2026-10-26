# Halon's review of a pull request, and each finding it verified and wrote, one at a time as it went. A review outlives
# the connection it read through, so the count of problems prevented still links to what was caught.
class CreatePullRequestReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_request_reviews, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :integration_environment, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :repository, null: false
      t.integer :number, null: false
      t.string :title
      t.string :url
      t.string :base_ref
      t.string :base_sha
      t.string :head_ref
      t.string :head_sha, null: false
      t.string :status, null: false, default: "queued"
      t.string :trigger, null: false
      t.boolean :rehearsal, null: false, default: false
      t.string :risk
      t.text :risk_reason
      t.text :summary
      t.jsonb :reviewed_paths, null: false, default: []
      t.jsonb :left_out, null: false, default: []
      t.string :summary_comment_id
      t.string :model
      t.string :provider
      t.string :model_override
      t.string :provider_override
      t.integer :max_spend_cents, null: false
      t.bigint :spent_micros, null: false, default: 0
      t.integer :turns_used, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.string :lease_holder
      t.datetime :lease_until
      t.string :error_summary
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :merged_at
      t.timestamps
    end
    add_index :pull_request_reviews, %i[workspace_id repository number], name: "index_pull_request_reviews_on_pull_request"
    add_index :pull_request_reviews, %i[workspace_id repository number], unique: true, where: "status IN ('queued', 'running') AND rehearsal = false",
                                                                         name: "index_pull_request_reviews_one_live"
    add_check_constraint :pull_request_reviews, "status IN ('queued', 'running', 'done', 'failed')", name: "pull_request_reviews_status"
    add_check_constraint :pull_request_reviews, "trigger IN ('requested', 'automatic')", name: "pull_request_reviews_trigger"
    add_check_constraint :pull_request_reviews, "risk IS NULL OR risk IN ('low', 'medium', 'high')", name: "pull_request_reviews_risk"

    create_table :pull_request_review_findings, id: :uuid do |t|
      t.references :pull_request_review, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :position, null: false
      t.string :fingerprint, null: false
      t.string :category, null: false
      t.string :severity, null: false
      t.string :effort, null: false
      t.text :claim, null: false
      t.text :why, null: false
      t.jsonb :failure_chain, null: false, default: []
      t.jsonb :evidence, null: false, default: []
      t.jsonb :checks, null: false, default: []
      t.jsonb :cross_checks, null: false, default: []
      t.string :path
      t.integer :line
      t.boolean :outside_diff, null: false, default: false
      t.text :suggested_fix
      t.text :agent_instructions
      t.string :status, null: false, default: "open"
      t.text :withdrawn_reason
      t.boolean :serious, null: false, default: false
      t.string :fixed_in_sha
      t.datetime :fixed_at
      t.string :host_comment_id
      t.uuid :lesson_id
      t.timestamps
    end
    add_index :pull_request_review_findings, %i[pull_request_review_id fingerprint], unique: true, name: "index_pull_request_review_findings_on_fingerprint"
    add_index :pull_request_review_findings, %i[pull_request_review_id position], unique: true, name: "index_pull_request_review_findings_in_order"
    add_index :pull_request_review_findings, :lesson_id
    add_check_constraint :pull_request_review_findings, "status IN ('open', 'fixed', 'withdrawn')", name: "pull_request_review_findings_status"
    add_check_constraint :pull_request_review_findings, "severity IN ('critical', 'major', 'minor', 'trivial')", name: "pull_request_review_findings_severity"
  end
end
