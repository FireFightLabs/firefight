# Pages and endpoints that need Halon, refused with why when the workspace has it off. A controller registers
# before_action :require_agent! where its other guards put it, and one that answers in JSON overrides
# refuse_without_agent.
module RequiresAgent
  extend ActiveSupport::Concern

  private

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    refuse_without_agent(Investigation.unavailable_reason(current_workspace))
  end

  def refuse_without_agent(reason)
    redirect_to dashboard_path, alert: reason
  end
end
