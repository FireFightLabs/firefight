# A member an admin removed keeps their row, so the incidents and history that name them stay, and reaches nothing.
class LetAdminsRemoveMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_memberships, :removed_at, :datetime
  end
end
