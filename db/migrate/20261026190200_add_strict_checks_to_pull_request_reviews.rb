# A finding a strict lesson produced fails a check on the pull request until it is fixed or a person overrides it, and
# the review keeps the check it last set so it is set again only when it changes. A high risk review is posted in the
# owning service's channel once.
class AddStrictChecksToPullRequestReviews < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :pull_request_review_findings, :chat_memories, column: :lesson_id, on_delete: :nullify
    add_reference :pull_request_review_findings, :overridden_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
    add_column :pull_request_review_findings, :overridden_at, :datetime
    add_column :pull_request_review_findings, :override_reason, :text

    add_column :pull_request_reviews, :commit_status, :string
    add_column :pull_request_reviews, :commit_status_sha, :string
    add_column :pull_request_reviews, :commit_status_error, :string
    add_column :pull_request_reviews, :high_risk_posted_at, :datetime
    add_column :pull_request_reviews, :high_risk_posted_channels, :jsonb, default: [], null: false
    add_check_constraint :pull_request_reviews, "commit_status IS NULL OR commit_status IN ('passing', 'failing')", name: "pull_request_reviews_commit_status"
  end
end
