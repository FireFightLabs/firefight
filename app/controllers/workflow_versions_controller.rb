# A workflow's versions from the canvas: throwing the draft away, and restoring an old version as a new draft. Both are
# building a draft, which members do without a grant. Publishing is WorkflowsController#publish.
class WorkflowVersionsController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: %i[discard restore]

  def discard
    version.discard!
    back_to_canvas(notice: "The draft of #{workflow.name} was discarded.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  def restore
    draft = version.restore!(by: current_membership)
    back_to_canvas(notice: "Version #{version.number} was restored as draft version #{draft.number}.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  private

  def version = @version ||= workflow.versions.find(params[:version_id])
end
