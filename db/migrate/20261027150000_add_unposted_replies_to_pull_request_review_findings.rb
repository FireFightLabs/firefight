# The replies Halon could not post on a finding's thread or as a comment on its pull request, each with why, kept so the
# review's page still shows what Halon would have said.
class AddUnpostedRepliesToPullRequestReviewFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_request_review_findings, :unposted_replies, :jsonb, null: false, default: []
  end
end
