# Halon reviews a pull request when someone asks, and a workspace can have it review every pull request when it opens, in
# every repository or only the ones chosen. What Halon posted is kept so it is posted once and edited after: the review
# itself once it went out, a serious finding's own comment, the replies it answered and the push it last checked a
# finding against.
class AddPullRequestReviewPosting < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :pull_request_reviews_on_open, :string, null: false, default: "off"
    add_column :workspaces, :pull_request_review_repositories, :string, array: true, null: false, default: []

    add_column :pull_request_reviews, :review_posted_at, :datetime
    add_column :pull_request_reviews, :review_comment_id, :string
    add_column :pull_request_review_findings, :serious_comment_id, :string
    add_column :pull_request_review_findings, :answered_comment_ids, :jsonb, null: false, default: []
    add_column :pull_request_review_findings, :rechecked_sha, :string
  end
end
