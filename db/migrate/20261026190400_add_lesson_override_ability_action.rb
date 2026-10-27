class AddLessonOverrideAbilityAction < ActiveRecord::Migration[8.1]
  # Listed in the grant picker from this row, so overriding a strict lesson can be granted before anyone looks for it.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(workspace_id: nil, key: Ability::Action::LESSON_OVERRIDE).destroy_all
  end
end
