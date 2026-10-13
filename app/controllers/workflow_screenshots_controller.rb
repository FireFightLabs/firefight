# A page a run's Browser step saw, served from the run's view to whoever may read the workflow, as a chat's are.
class WorkflowScreenshotsController < InertiaController
  include WorkflowCanvas
  include ServesChatAttachment

  authorizes Ability::Action::RESOURCE_WORKFLOWS, read: :show

  def show
    run = workflow.runs.find(params[:run_id])
    chats = Chat.where(owner_type: Workflow::Run::Step.name, owner_id: run.steps.select(:id))
    send_chat_attachment(Chat::Screenshot.where(chat_id: chats.select(:id)).find(params[:screenshot_id]))
  end
end
