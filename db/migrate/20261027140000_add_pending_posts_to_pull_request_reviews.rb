# What a review could not post while another of its posts waited on an approval, such as a reply on a thread or a line
# comment's edit, kept so it goes up once the approval is decided. And whether line comments a review posted could not be
# read back, so they are matched to their findings later and their threads are followed.
class AddPendingPostsToPullRequestReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :pull_request_reviews, :pending_posts, :jsonb, null: false, default: []
    add_column :pull_request_reviews, :comments_unread, :boolean, null: false, default: false
  end
end
