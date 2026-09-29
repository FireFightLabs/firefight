# A rehearsal of a bug that was later fixed reads each repository as of the commit before the fix, so the fix cannot be
# found. Empty for every other run.
class AddCodeAsOfToInvestigations < ActiveRecord::Migration[8.1]
  def change
    add_column :investigations, :code_as_of, :jsonb, null: false, default: {}
  end
end
