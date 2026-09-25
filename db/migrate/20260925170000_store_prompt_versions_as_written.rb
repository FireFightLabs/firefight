# A prompt version is the first 12 hex characters of its wording's digest, and an integer column kept only the digits it
# began with, so no ledger row could be matched to its wording. What was kept names nothing and is cleared.
class StorePromptVersionsAsWritten < ActiveRecord::Migration[8.1]
  def up
    change_column :inferences, :prompt_version, :string, using: "NULL"
  end

  def down
    change_column :inferences, :prompt_version, :integer, using: "NULL"
  end
end
