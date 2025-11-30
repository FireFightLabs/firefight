module Auth
  class OmniauthCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token, only: :slack

    def slack
      auth_hash = request.env["omniauth.auth"]

      ActiveRecord::Base.transaction do
        # Find or create workspace from Slack team
        workspace = Workspace.find_or_create_from_slack!(auth_hash)

        # Find or create user from Slack user
        user = User.find_or_create_from_omniauth!(auth_hash)

        # Create or update membership (first user = owner, rest = member)
        membership = WorkspaceMembership.find_or_create_from_omniauth!(
          user,
          workspace,
          auth_hash
        )

        # Set session
        session[:user_id] = user.id
        session[:workspace_id] = workspace.id
      end

      redirect_to dashboard_path, notice: "Successfully signed in with Slack!"
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
