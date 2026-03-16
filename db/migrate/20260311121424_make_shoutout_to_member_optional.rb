class MakeShoutoutToMemberOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :shoutouts, :to_member_id, true
  end
end
