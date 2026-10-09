# Whether the founder's letter was seen moves from the session to the workspace. A workspace already past the letter,
# with its setup finished or any step of the checklist answered, is kept as having seen it, so it is not shown again.
# One with no progress yet has not left the letter behind and still shows it.
class AddFounderLetterSeenAtToWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def up
    add_column :workspace_onboardings, :founder_letter_seen_at, :datetime

    execute <<~SQL.squish
      UPDATE workspace_onboardings SET founder_letter_seen_at = now()
      WHERE founder_letter_seen_at IS NULL
        AND (completed_at IS NOT NULL
          OR checklist_completed_at IS NOT NULL
          OR ai_choice IS NOT NULL
          OR ai_chosen_at IS NOT NULL
          OR stack_done_at IS NOT NULL
          OR stack_answers <> '{}'::jsonb
          OR permissions_reviewed_at IS NOT NULL
          OR halon_answered_at IS NOT NULL
          OR chat_skipped_at IS NOT NULL
          OR dialog_dismissed_at IS NOT NULL
          OR walkthrough_step IS NOT NULL)
    SQL
  end

  def down
    remove_column :workspace_onboardings, :founder_letter_seen_at
  end
end
