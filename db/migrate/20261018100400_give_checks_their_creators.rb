# Every check made before owners is owned by whoever made it. One whose creator already left is paused, and the next
# sweep tells the workspace's admins.
class GiveChecksTheirCreators < ActiveRecord::Migration[8.1]
  def up
    Investigation::Check.reset_column_information
    Investigation::Check.adopt_creators!
  end

  def down
  end
end
