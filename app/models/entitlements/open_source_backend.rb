module Entitlements
  class OpenSourceBackend
    def check(_workspace, _feature)
      Entitlements.allow
    end
  end
end
