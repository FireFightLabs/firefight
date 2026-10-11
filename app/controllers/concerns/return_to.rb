# Where a flow that leaves Firefight, such as connecting a tool or paying for credits, brings the person back to. Only a
# chat on this dashboard or the setup checklist, so a crafted link cannot send someone elsewhere afterwards.
module ReturnTo
  extend ActiveSupport::Concern

  private

  def return_to_param = safe_return_to(params[:return_to])

  def safe_return_to(path)
    path = path.to_s
    return nil unless path.start_with?("/") && !path.start_with?("//")

    route = Rails.application.routes.recognize_path(path)
    chat = route[:controller] == AgentChatsController.controller_path && %w[index show].include?(route[:action])
    setup = route[:controller] == SetupController.controller_path && route[:action] == "show"
    path if chat || setup
  rescue ActionController::RoutingError
    nil
  end
end
