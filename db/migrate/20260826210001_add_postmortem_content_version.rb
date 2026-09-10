# Guards only the whole-document replace. Status, generation state and the message id
# cannot conflict with it.
class AddPostmortemContentVersion < ActiveRecord::Migration[8.1]
  def change
    add_column :postmortems, :content_version, :integer, default: 0, null: false
  end
end
