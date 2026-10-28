# A refusal remembers where it stands (waiting to be posted, held for an approval, posted, unconfirmed, or dropped and
# why), when it was first sent, so a retry reads the conversation before posting again, and which approval holds it. A
# finding keeps the thread's refusal for good, so later replies stay on the review's page.
class AddRefusalStates < ActiveRecord::Migration[8.1]
  def change
    change_table :pull_request_review_refusals, bulk: true do |t|
      t.string :status, null: false, default: "pending"
      t.text :dropped_reason
      t.datetime :attempted_at
      t.uuid :held_approval_id
    end
    add_check_constraint :pull_request_review_refusals, "status IN ('pending', 'held', 'posted', 'unconfirmed', 'dropped')", name: "pull_request_review_refusals_status"
    add_index :pull_request_review_refusals, "workspace_id, lower(repository), number", name: "index_pull_request_review_refusals_on_pull_request"
    # A refusal from before that went up is posted. One that never did and is over an hour old has no job left to post
    # it, so it is dropped rather than silencing the next request.
    reversible do |direction|
      direction.up do
        execute "UPDATE pull_request_review_refusals SET status = 'posted' WHERE posted_at IS NOT NULL"
        execute "UPDATE pull_request_review_refusals SET status = 'dropped', dropped_reason = 'Never posted before refusals kept their state.' " \
                "WHERE posted_at IS NULL AND created_at < now() - interval '1 hour'"
      end
    end

    change_table :pull_request_review_findings, bulk: true do |t|
      t.text :thread_refusal
      t.datetime :thread_refused_at
    end
  end
end
