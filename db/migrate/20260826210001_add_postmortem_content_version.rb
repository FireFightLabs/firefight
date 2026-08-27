# Guards the one write that replaces the whole document. Status, generation
# state and the Slack message id are untouched, so they cannot conflict with a
# rewrite or with each other.
class AddPostmortemContentVersion < ActiveRecord::Migration[8.1]
  def change
    add_column :postmortems, :content_version, :integer, default: 0, null: false
  end
end
