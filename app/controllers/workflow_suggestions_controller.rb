# Halon's suggested changes to a workflow, a change set at a time: accepted into the draft, which is published like any
# change, or dismissed, the whole set or none of it. Two people deciding at once decide once.
class WorkflowSuggestionsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKFLOWS, update: %i[accept dismiss]

  include RequiresWorkflows

  before_action :set_edits

  def accept
    Workflow::Edit.transaction { @edits.each { |edit| edit.accept!(by: current_membership) } }
    redirect_back fallback_location: workflow_path(@workflow), notice: "Halon's suggestion was added to the draft of #{@workflow.name}. Publish it to use it."
  rescue Workflow::Edit::Refused => refused
    redirect_back fallback_location: workflow_path(@workflow), alert: refused.message
  end

  def dismiss
    Workflow::Edit.transaction { @edits.each { |edit| edit.dismiss!(by: current_membership) } }
    redirect_back fallback_location: workflow_path(@workflow), notice: "Halon's suggestion for #{@workflow.name} was dismissed."
  rescue Workflow::Edit::Refused => refused
    redirect_back fallback_location: workflow_path(@workflow), alert: refused.message
  end

  private

  def set_edits
    @workflow = current_workspace.workflows.find(params[:workflow_id])
    @edits = @workflow.proposals.where(change_set_id: params[:id]).to_a
    raise ActiveRecord::RecordNotFound, "No suggestion #{params[:id]}" if @edits.empty?
  end
end
