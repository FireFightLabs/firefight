class LeaseInvestigationsToOneWorker < ActiveRecord::Migration[8.1]
  def change
    # A retried job could otherwise run alongside the worker it was meant to replace.
    add_column :investigations, :lease_token, :uuid
    add_column :investigations, :lease_until, :datetime
    # Named by the agent when it concludes, so a partial finding says what it could not check.
    add_column :investigation_findings, :gaps, :text
  end
end
