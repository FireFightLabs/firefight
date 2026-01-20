module Auth
  class OmniauthCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token, only: :slack

    def slack
      auth_hash = request.env["omniauth.auth"]

      service = SlackAuthenticationService.new
      result = service.process_oauth_callback(auth_hash)

      session[:user_id] = result[:user].id
      session[:workspace_id] = result[:workspace].id

      notice = result[:first_install] ? "Setting up your FireFight workspace..." : "Successfully signed in with Slack!"
      redirect_to dashboard_path, notice: notice
    rescue => e
      Rails.logger.error "Slack OAuth failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to login_path, alert: "Authentication failed. Please try again."
    end

    def failure
      error_message = case params[:message]
      when "csrf_detected"
        "Authentication session expired. Please try again."
      when "access_denied"
        "You denied access to your Slack account."
      when "invalid_credentials"
        "Invalid credentials. Please contact support."
      else
        "Authentication failed. Please try again."
      end

      redirect_to login_path, alert: error_message
    end
  end
end
