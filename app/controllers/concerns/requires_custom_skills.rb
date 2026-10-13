# Pages and endpoints for the workspace's own skills, which a workspace without the custom skills flag never sees. They
# answer as a page that does not exist, ahead of anything checking who is asking, as the workflows pages do.
module RequiresCustomSkills
  extend ActiveSupport::Concern

  included do
    prepend_before_action :require_custom_skills!
  end

  private

  def require_custom_skills!
    return if current_workspace && Chat::CustomSkill.enabled_for?(current_workspace)

    raise ActionController::RoutingError, "Not Found"
  end
end
