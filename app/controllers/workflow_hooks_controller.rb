# A workflow's own address for its inbound webhook trigger, from the canvas: its secret, fetched only when someone who
# may change the workflow asks for it so it never rides in the page, and a new address, which retires the old one and
# its secret at once.
class WorkflowHooksController < InertiaController
  include WorkflowCanvas

  authorizes Ability::Action::RESOURCE_WORKFLOWS, update: %i[secret replace]

  def secret
    render json: { url: workflow.hook_url, secret: workflow.hook_secret }
  end

  def replace
    workflow.replace_hook!
    back_to_canvas(notice: "#{workflow.name} has a new webhook address and secret. The old ones no longer start it.")
  end
end
