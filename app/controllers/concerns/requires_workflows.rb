# Pages and endpoints for workflows and the workspace's own skills, which a workspace without the workflows flag never
# sees. They answer as a page that does not exist, so nothing about them shows.
module RequiresWorkflows
  extend ActiveSupport::Concern

  private

  def require_workflows!
    return if FeatureFlags.enabled?(current_workspace, FeatureFlags::WORKFLOWS)

    raise ActionController::RoutingError, "Not Found"
  end
end
