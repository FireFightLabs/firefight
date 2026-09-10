# Reached through `exceptions_app` and the catch-all route, so a mistyped path is a
# styled page in every environment.
class ErrorsController < InertiaController
  # Error pages render for everyone, suspended or not.
  skip_before_action :block_suspended_workspace
  skip_before_action :require_authentication
  def not_found
    respond_with_error("errors/not-found", :not_found)
  end

  def unprocessable
    respond_with_error("errors/unprocessable", :unprocessable_content)
  end

  def server_error
    respond_with_error("errors/server-error", :internal_server_error)
  end

  private

  # An API path must not answer with a page, and a missing image or script only needs the status.
  def respond_with_error(component, status)
    respond_to do |format|
      format.html { render inertia: component, props: { signedIn: user_signed_in? }, status: status }
      format.json { render json: { error: status.to_s }, status: status }
      format.any { head status }
    end
  end
end
