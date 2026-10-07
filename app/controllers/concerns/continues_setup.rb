# An admin whose workspace has not finished setup is sent back to the checklist from any page, so it cannot be
# dismissed. Only page visits are turned around. A form's request, a JSON read and a controller that is part of setup
# itself (the chat Halon is met in, a sign-in callback) skip it. Whatever the redirected page was going to say, such as
# "Slack is connected", is kept for the checklist to say instead.
module ContinuesSetup
  extend ActiveSupport::Concern

  included do
    before_action :continue_setup
  end

  private

  def continue_setup
    return unless request.get? && request.format.html? && current_membership

    onboarding = current_workspace.onboarding
    return unless onboarding&.steers?(current_membership)
    return if onboarding.finish_if_done!

    flash.keep
    redirect_to onboarding_checklist_path
  end
end
