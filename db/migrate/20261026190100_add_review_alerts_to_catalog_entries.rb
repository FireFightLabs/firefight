# A pull request Halon reviews as high risk is also posted in the channel of the service that owns its repository,
# unless that service turned it off.
class AddReviewAlertsToCatalogEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_entries, :review_alerts, :boolean, default: true, null: false
  end
end
