# A refusal remembers where it stands (waiting to be posted, held for an approval, posted, or dropped and why), when it
# was first tried, so a retry reads the conversation before posting again, and which approval holds it. A finding keeps
# the thread's refusal for good, so later replies stay on the review's page.
class AddRefusalStates < ActiveRecord::Migration[8.1]
  def change
    change_table :pull_request_review_refusals, bulk: true do |t|
      t.string :status, null: false, default: "pending"
      t.text :dropped_reason
      t.datetime :attempted_at
      t.uuid :held_approval_id
    end
    add_check_constraint :pull_request_review_refusals, "status IN ('pending', 'held', 'posted', 'dropped')", name: "pull_request_review_refusals_status"
    add_index :pull_request_review_refusals, %i[workspace_id repository number], name: "index_pull_request_review_refusals_on_pull_request"
    reversible do |direction|
      direction.up { execute "UPDATE pull_request_review_refusals SET status = 'posted' WHERE posted_at IS NOT NULL" }
    end

    change_table :pull_request_review_findings, bulk: true do |t|
      t.text :thread_refusal
      t.datetime :thread_refused_at
    end
  end
end
