module Entitlements
  class OpenSourceBackend
    def check(_workspace, _feature)
      Entitlements.allow
    end

    def ai_account(_workspace) = Entitlements::AI_ACCOUNT_OPERATOR
  end
end
