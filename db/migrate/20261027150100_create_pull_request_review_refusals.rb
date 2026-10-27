# A review a person asked for on a pull request that could not start, and the comment Halon posted there to say why. One
# row per request, so a delivery sent again never says it twice.
class CreatePullRequestReviewRefusals < ActiveRecord::Migration[8.1]
  def change
    create_table :pull_request_review_refusals, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :integration_environment, type: :uuid, foreign_key: { on_delete: :nullify }, index: { name: "index_pull_request_review_refusals_on_environment" }
      t.string :repository, null: false
      t.integer :number, null: false
      t.string :reference, null: false
      t.string :reason, null: false
      t.string :comment_id
      t.datetime :posted_at
      t.timestamps
    end
    add_index :pull_request_review_refusals, %i[workspace_id reference], unique: true, name: "index_pull_request_review_refusals_once"
  end
end
