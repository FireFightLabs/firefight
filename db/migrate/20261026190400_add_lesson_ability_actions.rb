class AddLessonAbilityActions < ActiveRecord::Migration[8.1]
  # Listed in the grant picker from these rows, so deciding on lessons and overriding a strict one can be granted before
  # anyone looks for them.
  def up
    Ability::Action.sync_system_actions!
  end

  def down
    Ability::Action.where(workspace_id: nil, key: [ Ability::Action::LESSON_DECIDE, Ability::Action::LESSON_OVERRIDE ]).destroy_all
  end
end
