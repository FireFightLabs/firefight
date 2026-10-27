# A post an approval rule holds waits on that one approval, so no second approval opens for the same review while it is
# pending. Each finding keeps what was said on its thread, Halon's replies and the people it answered, so a reply to any
# of them is known as the thread's and its answer reads the thread so far. A finding on a public repository is posted
# with its why and failure chain written in code terms only, kept beside the full ones the dashboard shows.
class AddHeldPostsAndThreadsToPullRequestReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_request_reviews, :held_approval_id, :uuid
    add_column :pull_request_review_findings, :thread_said, :jsonb, null: false, default: []
    add_column :pull_request_review_findings, :public_why, :text
    add_column :pull_request_review_findings, :public_failure_chain, :jsonb
  end
end
