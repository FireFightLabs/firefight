# Base for every operator console page. A user not listed in OPERATOR_USER_IDS gets the app's not found page, so the
# console does not reveal that it exists. An operator then enters an authenticator code, again after
# Credential::VERIFIED_FOR.
module Operator
  class BaseController < ApplicationController
    before_action :require_operator!
    before_action :require_second_factor!

    inertia_share do
      { operator: current_user && { name: current_user.name.presence || current_user.email, email: current_user.email } }
    end
    # Number of Needs attention items in the last 24 hours, shown in the sidebar. Computed only when a page renders.
    inertia_share attention: -> { Attention.new(Filter.new, jobs: JobHealth.read(since: Filter.new.since)).items.size }

    private

    def require_operator!
      return if Credential.operator?(current_user)

      respond_to do |format|
        format.html { render inertia: "errors/not-found", props: { signedIn: user_signed_in? }, status: :not_found }
        format.any { head :not_found }
      end
    end

    def require_second_factor!
      return if operator_verified?

      session[:operator_return_to] = request.fullpath if request.get? || request.head?
      # Flightdeck runs this check too, and inside Flightdeck only main_app has the console's routes.
      redirect_to Credential.for(current_user)&.confirmed? ? main_app.operator_verify_path : main_app.operator_setup_path
    end

    def operator_verified?
      stamp = session[:operator_verified]
      stamp.is_a?(Hash) && stamp["user_id"] == current_user.id && stamp["until"].to_i > Time.current.to_i
    end

    def filter = @filter ||= Filter.from(params)

    # The selected window and workspace, and the choices for both pickers.
    def filter_props
      { filter: filter.to_h, windows: Filter::WINDOWS.keys, workspaces: Workspace.order(:name).map { |workspace| { id: workspace.id, name: workspace.name } } }
    end

    # Turns a value object into a hash with camelCase keys for the page. Only the top level keys change, so nested
    # hashes keyed by data, such as error class names, keep their keys.
    def camelized(value)
      value && value.to_h.transform_keys { |key| key.to_s.camelize(:lower) }
    end

    # Recorded as the actor on anything an operator changes, such as a paused workflow.
    def operator_label = "#{current_user.email} (operator)"

    def mark_verified!
      session[:operator_verified] = { "user_id" => current_user.id, "until" => Credential::VERIFIED_FOR.from_now.to_i }
    end
  end
end
