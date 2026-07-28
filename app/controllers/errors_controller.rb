# Renders the branded error pages. Reached two ways: `exceptions_app` routes
# here when Rails handles an exception itself, and the catch-all route sends an
# unmatched URL to `not_found` so a mistyped path is a styled page rather than a
# routing error in any environment.
class ErrorsController < InertiaController
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

  # A missing API path must not answer with a page, and an image or script that
  # 404s only needs the status.
  def respond_with_error(component, status)
    respond_to do |format|
      format.html { render inertia: component, props: { signedIn: user_signed_in? }, status: status }
      format.json { render json: { error: status.to_s }, status: status }
      format.any { head status }
    end
  end
end
