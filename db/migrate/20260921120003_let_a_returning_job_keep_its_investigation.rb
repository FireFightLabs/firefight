class LetAReturningJobKeepItsInvestigation < ActiveRecord::Migration[8.1]
  # The queue only hands a job out again once its worker is gone, so the job that holds a run may
  # take it back without waiting out the lease. attempts is what stops a run that kills every worker.
  def change
    add_column :investigations, :lease_holder, :string
    add_column :investigations, :attempts, :integer, null: false, default: 0
  end
end
