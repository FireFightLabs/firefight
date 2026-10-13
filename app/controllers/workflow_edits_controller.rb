# One change made on the canvas: a step added, removed, moved, connected, renamed or set up, or the trigger changed. It
# names the draft revision the person saw, so a change someone made since to the same step refuses it with who did.
class WorkflowEditsController < InertiaController
  include WorkflowCanvas
  include FreeFormParams

  authorizes Ability::Action::RESOURCE_WORKFLOWS, create: :create

  def create
    edit = workflow.edit!(operation: params[:operation].to_s, payload: object_param(params[:payload]) || {}, by: current_membership,
                          base_revision: params[:base_revision].presence&.to_i)
    back_to_canvas(notice: edit.notice)
  rescue Workflow::Edit::Refused => error
    back_to_canvas(alert: error.message)
  rescue ActiveRecord::RecordInvalid => error
    back_to_canvas(alert: error.record.errors.full_messages.to_sentence)
  end
end
