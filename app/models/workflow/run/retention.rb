# A run's details, what each step took in and gave back and the results it kept, are dropped once the run has been over
# for the workspace's retention, 90 days unless it chose otherwise. The run itself stays for good as its one line: when,
# what started it, the version, how it ended and who it acted as. A run still going is never touched, and a pinned run
# keeps everything.
module Workflow::Run::Retention
  extend ActiveSupport::Concern

  DAYS = (1..400)
  DEFAULT_DAYS = 90

  class_methods do
    # Runs of the workspace whose details are past its retention, as the sweep reads them.
    def past_retention(workspace)
      where(workspace: workspace, status: Workflow::Run::FINISHED, pinned: false, details_pruned_at: nil)
        .where(finished_at: ...workspace.workflow_run_retention_days.days.ago)
    end

    # Returns how many runs lost their details.
    def prune_details!(workspace)
      past_retention(workspace).find_each.count(&:prune_details!)
    end
  end

  # Claimed with one update guarded on the run still being finished, unpinned and whole, so a run an operator takes up
  # again or a person pins in the meantime keeps its details.
  def prune_details!
    transaction do
      claimed = self.class.where(id: id, status: Workflow::Run::FINISHED, pinned: false, details_pruned_at: nil)
                          .update_all(details_pruned_at: Time.current, inputs: {}, outputs: nil, trigger_payload: {}, updated_at: Time.current) == 1
      raise ActiveRecord::Rollback unless claimed

      Chat.where(owner_type: Workflow::Run::Step.name, owner_id: Workflow::Run::Step.where(run_id: id).select(:id)).destroy_all
      Workflow::Run::Step.where(run_id: id).delete_all
      Chat::SavedResult.where(workflow_run_id: id).delete_all
      true
    end.tap { reload }
  end

  def details_pruned? = details_pruned_at.present?
end
