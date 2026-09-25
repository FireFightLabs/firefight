# The operator console. Only a user listed in OPERATOR_USER_IDS gets past the first check, and anyone else sees the
# app's own not found page, so the console does not reveal it exists. Past that, an authenticator code is asked for
# again every OperatorCredential::VERIFIED_FOR, so a taken-over sign-in alone opens nothing.
module Operator
  class BaseController < ApplicationController
    before_action :require_operator!
    before_action :require_second_factor!

    private

    def require_operator!
      return if OperatorCredential.operator?(current_user)

      respond_to do |format|
        format.html { render inertia: "errors/not-found", props: { signedIn: user_signed_in? }, status: :not_found }
        format.any { head :not_found }
      end
    end

    def require_second_factor!
      return if operator_verified?

      session[:operator_return_to] = request.fullpath if request.get? || request.head?
      # Flightdeck runs these checks too, where only main_app knows the console's routes.
      redirect_to current_user.operator_credential&.confirmed? ? main_app.operator_verify_path : main_app.operator_setup_path
    end

    def operator_verified?
      stamp = session[:operator_verified]
      stamp.is_a?(Hash) && stamp["user_id"] == current_user.id && stamp["until"].to_i > Time.current.to_i
    end

    def mark_verified!
      session[:operator_verified] = { "user_id" => current_user.id, "until" => OperatorCredential::VERIFIED_FOR.from_now.to_i }
    end
  end
end
