# Firefight's library of workflows, each with its version: use one as it is, which moves with each new version, or copy
# it to make it the workspace's own. It is the Library tab of the Workflows page (WorkflowsController), where the
# workspace's workflows show whether each follows the library, and a copy shows what changed in a newer version to take
# or leave. Any workflow exports as a file, and a file imports as a new one. Each action here answers back to that tab.
class HalonWorkflowLibraryController < InertiaController
  include RequiresAgent

  before_action :require_agent!

  authorizes Ability::Action::RESOURCE_WORKFLOWS,
    read: %i[index export],
    create: %i[adopt import],
    update: %i[take_library keep_own]

  UNANSWERED = "Answer this to use it.".freeze

  # The library's own address, from before it was a tab.
  def index = redirect_to(library_tab)

  # following is whether it moves with each new version, the default, or is the workspace's own copy. answers are what
  # the person said to each question the item asks, such as what a scheduled check looks at.
  def adopt
    item = Workflow::Library.find(params[:key]) || raise(ActiveRecord::RecordNotFound)
    answers = params.fetch(:answers, {}).permit(*Workflow::Trigger.input_keys(item.trigger)).to_h
    unanswered = Workflow.unanswered_library_inputs(item, answers)
    return form_refused_with(unanswered.to_h { |key| [ :"answers.#{key}", [ UNANSWERED ] ] }) if unanswered.any?

    following = ActiveModel::Type::Boolean.new.cast(params.fetch(:following, true))
    workflow = Workflow.from_library!(item, workspace: current_workspace, by: current_membership, name: params[:name].presence || item.name,
                                      following: following, answers: answers)
    redirect_to library_tab, notice: used_notice(workflow)
  rescue Workflow::Edit::Refused => error
    form_refused_with(name: [ error.message ])
  rescue ActiveRecord::RecordInvalid => error
    form_refused_with(name: error.record.errors.full_messages)
  end

  def take_library
    workflow = workflows.find(params[:id])
    draft = workflow.take_library!(by: current_membership)
    redirect_to library_tab,
                notice: "#{workflow.name} has a new draft, version #{draft.number}, holding Firefight's version #{workflow.library_version}. Publish it to run it."
  rescue Workflow::Edit::Refused => error
    redirect_to library_tab, alert: error.message
  end

  def keep_own
    workflow = workflows.find(params[:id])
    workflow.keep_own!
    redirect_to library_tab, notice: "#{workflow.name} keeps your steps. You are told again when Firefight ships a newer version."
  rescue Workflow::Edit::Refused => error
    redirect_to library_tab, alert: error.message
  end

  def export
    workflow = workflows.includes(:live_version).find(params[:id])
    send_data Workflow::Document.render(workflow), filename: Workflow::Document.file_name(workflow), type: "application/json", disposition: "attachment"
  end

  def import
    parsed = Workflow::Document.parse(uploaded_text)
    workflow = Workflow::Document.import!(parsed, workspace: current_workspace, by: current_membership, name: params[:name])
    redirect_to library_tab, notice: "#{workflow.name} was imported as a draft. Publish it to run it."
  rescue Workflow::Document::Unreadable => error
    form_refused_with(file: [ error.message ])
  rescue ActiveRecord::RecordInvalid => error
    form_refused_with(file: error.record.errors.full_messages)
  end

  private

  def workflows = Workflow.where(workspace: current_workspace)

  def library_tab = halon_workflows_path(WorkflowsController::TAB_QUERY => WorkflowsController::TAB_LIBRARY)

  def used_notice(workflow)
    return "#{workflow.name} was copied from Firefight's library as your own. Change its draft and publish it to run it." unless workflow.follows_library?

    "#{workflow.name} was made from Firefight's library and moves with its new versions. Publish its draft to run it."
  end

  def uploaded_text
    file = params[:file]
    raise Workflow::Document::Unreadable, "Choose a workflow file to import." unless file.respond_to?(:read)

    file.read(Workflow::Document::SIZE_LIMIT + 1)
  end

  def form_refused_with(errors) = redirect_back_or_to(library_tab, inertia: { errors: errors })
end
