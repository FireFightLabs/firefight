class AddFounderLetterSeenAtToWorkspaceOnboardings < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_onboardings, :founder_letter_seen_at, :datetime
  end
end
