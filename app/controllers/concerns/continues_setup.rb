# An admin whose workspace has not finished setup is sent back to the checklist from any page, so it cannot be
# dismissed. Only page visits are turned around. A form's request, a JSON read and a controller that is part of setup
# itself (the chat Halon is met in, a sign-in callback) skip it, and so does a page that stays open while the workspace
# is closed, such as where a hosted build sells its plan and credits, so paying from setup never loops back here.
# Whatever the redirected page was going to say, such as "Slack is connected", is kept for the checklist to say instead.
module ContinuesSetup
  extend ActiveSupport::Concern

  included do
    before_action :continue_setup
  end

  private

  def continue_setup
    return unless request.get? && request.format.html? && current_membership
    return if opens_while_closed?

    onboarding = current_workspace.onboarding
    return unless onboarding&.steers?(current_membership)
    return if onboarding.finish_if_done!

    flash.keep
    redirect_to onboarding_checklist_path
  end

  def opens_while_closed?
    __callbacks[:process_action].none? { |callback| callback.filter == :block_inaccessible_workspace }
  end
end
