# Undo Halon's change: one change of Halon's, or every change it made to the open draft or the live version, taken back
# out as a person's edits, so what people did around it stays.
class WorkflowUndosController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: :create

  def create
    halon_edits = chosen_edits
    workflow.undo_halon!(halon_edits, by: current_membership)
    changes = halon_edits.map { |edit| edit.change_set_id || edit.id }.uniq.size
    back_to_canvas(notice: changes == 1 ? "Halon's change was undone." : "Halon's changes were undone.")
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  end

  private

  # The edits of one change of Halon's when named, or every one of Halon's the canvas lists as undoable.
  def chosen_edits
    landed = workflow.edits.landed.where(author_kind: Workflow::AUTHOR_HALON)
    return landed.where(change_set_id: params[:change_set_id]).to_a if params[:change_set_id].present?
    return landed.where(id: params[:edit_id]).to_a if params[:edit_id].present?

    landed.where(version_id: workflow.undoable_version_ids).to_a
  end
end
