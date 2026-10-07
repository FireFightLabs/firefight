# Serves the token Faylee reads to confirm this deployment owns its domain.
class FayleeController < ActionController::API
  def verification
    token = Rails.configuration.x.faylee_verification_token
    return head(:not_found) unless token

    render plain: token
  end
end
