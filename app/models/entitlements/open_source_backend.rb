module Entitlements
  # Default backend for the open-source / self-hosted build: every feature is
  # available, always. Self-hosting is the free offering — there is no trial or
  # plan to enforce. The Cloud engine replaces this with a backend that gates on
  # trial state, plan, and AI credit balance.
  class OpenSourceBackend
    def check(_workspace, _feature)
      Entitlements.allow
    end
  end
end
