# Firefight's library of workflows, each with its version: use one as it is, which moves with each new version, or copy
# it to make it the workspace's own. The workspace's workflows show whether each follows the library, and a copy shows
# what changed in a newer version to take or leave. Any workflow exports as a file, and a file imports as a new one.
class HalonWorkflowLibraryController < InertiaController
  include RequiresAgent
  include RequiresWorkflows

  before_action :require_agent!

  authorizes Ability::Action::RESOURCE_WORKFLOWS,
    read: %i[index export],
    create: %i[adopt import],
    update: %i[take_library keep_own]

  def index
    render inertia: "halon/workflow-library", props: {
      items: HalonLibraryWorkflowSerializer.many(Workflow::Library.all, used: used_by_item),
      workflows: HalonLibraryWorkflowUseSerializer.many(workflows.includes(:live_version).ordered.to_a)
    }
  end

  # following is whether it moves with each new version, the default, or is the workspace's own copy.
  def adopt
    item = Workflow::Library.find(params[:key]) || raise(ActiveRecord::RecordNotFound)
    following = ActiveModel::Type::Boolean.new.cast(params.fetch(:following, true))
    workflow = Workflow.from_library!(item, workspace: current_workspace, by: current_membership, name: params[:name].presence || item.name, following: following)
    redirect_to halon_workflow_library_path, notice: used_notice(workflow)
  rescue Workflow::Edit::Refused => error
    form_refused_with(name: [ error.message ])
  rescue ActiveRecord::RecordInvalid => error
    form_refused_with(name: error.record.errors.full_messages)
  end

  def take_library
    workflow = workflows.find(params[:id])
    draft = workflow.take_library!(by: current_membership)
    redirect_to halon_workflow_library_path,
                notice: "#{workflow.name} has a new draft, version #{draft.number}, holding Firefight's version #{workflow.library_version}. Publish it to run it."
  rescue Workflow::Edit::Refused => error
    redirect_to halon_workflow_library_path, alert: error.message
  end

  def keep_own
    workflow = workflows.find(params[:id])
    workflow.keep_own!
    redirect_to halon_workflow_library_path, notice: "#{workflow.name} keeps your steps. You are told again when Firefight ships a newer version."
  rescue Workflow::Edit::Refused => error
    redirect_to halon_workflow_library_path, alert: error.message
  end

  def export
    workflow = workflows.includes(:live_version).find(params[:id])
    send_data Workflow::Document.render(workflow), filename: Workflow::Document.file_name(workflow), type: "application/json", disposition: "attachment"
  end

  def import
    parsed = Workflow::Document.parse(uploaded_text)
    workflow = Workflow::Document.import!(parsed, workspace: current_workspace, by: current_membership, name: params[:name])
    redirect_to halon_workflow_library_path, notice: "#{workflow.name} was imported as a draft. Publish it to run it."
  rescue Workflow::Document::Unreadable => error
    form_refused_with(file: [ error.message ])
  rescue ActiveRecord::RecordInvalid => error
    form_refused_with(file: error.record.errors.full_messages)
  end

  private

  def workflows = Workflow.where(workspace: current_workspace)

  # The workspace's workflows made from each item, by key, so a list never asks per row.
  def used_by_item = workflows.where.not(library_key: nil).pluck(:library_key, :name).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

  def used_notice(workflow)
    return "#{workflow.name} was copied from Firefight's library as your own. Change its draft and publish it to run it." unless workflow.follows_library?

    "#{workflow.name} was made from Firefight's library and moves with its new versions. Publish its draft to run it."
  end

  def uploaded_text
    file = params[:file]
    raise Workflow::Document::Unreadable, "Choose a workflow file to import." unless file.respond_to?(:read)

    file.read(Workflow::Document::SIZE_LIMIT + 1)
  end

  def form_refused_with(errors) = redirect_back_or_to(halon_workflow_library_path, inertia: { errors: errors })
end
