# Where a finding's own comment can be opened on the code host, as the host gave it when the comment was posted, so the
# count of problems prevented links to it even after the connection it was posted through is gone.
class AddHostCommentUrlToPullRequestReviewFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_request_review_findings, :host_comment_url, :string
  end
end
