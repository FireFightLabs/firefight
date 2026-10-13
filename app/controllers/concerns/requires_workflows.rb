# Pages and endpoints for workflows and the workspace's own skills, which a workspace without the workflows flag never
# sees. They answer as a page that does not exist, so nothing about them shows, and before anything checks who is
# asking, so a person who may not use one is not told it is there.
module RequiresWorkflows
  extend ActiveSupport::Concern

  # Ahead of authorization, so a person who may not use one is told it is not there rather than that they may not.
  included do
    prepend_before_action :require_workflows!
  end

  private

  def require_workflows!
    return if current_workspace && FeatureFlags.enabled?(current_workspace, FeatureFlags::WORKFLOWS)

    raise ActionController::RoutingError, "Not Found"
  end
end
