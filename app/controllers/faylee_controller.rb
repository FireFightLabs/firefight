class FayleeController < ActionController::Base
  def verification
    token = ENV["FAYLEE_VERIFICATION_TOKEN"]

    if token
      render plain: token
    else
      head :not_found
    end
  end
end
