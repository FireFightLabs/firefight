module Entitlements
  class OpenSourceBackend
    def check(_workspace, _feature)
      Entitlements.allow
    end

    def ai_account(_workspace) = Entitlements::AI_ACCOUNT_OPERATOR

    def next_step_path(_workspace) = nil

    def private_ai_endpoints?(_workspace) = true
  end
end
