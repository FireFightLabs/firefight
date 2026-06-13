# Per-workspace entitlement gate for paid or usage-limited features.
#
# This is the public seam the proprietary Cloud engine plugs into. In the
# open-source build the default backend allows everything — self-hosting is the
# free offering, so there is no trial or plan to enforce. The Cloud engine swaps
# in its own backend to enforce trials, plan limits, and AI credit caps:
#
#   Entitlements.backend = FirefightCloud::EntitlementsBackend.new
#
# A backend implements a single method returning an Entitlements::Result:
#
#   check(workspace, feature) -> Entitlements::Result
#
# Callers gate a feature with `check` and surface `message` on a denial:
#
#   gate = Entitlements.check(workspace, Entitlements::AI)
#   return Command.ephemeral(gate.message) if gate.blocked?
#
# `feature` is always one of the constants below, never a raw string. There is
# one AI key today because AI usage shares a single credit/trial policy; split
# it (e.g. a Pro-only investigator) only when a feature needs its own rule.
module Entitlements
  AI = "ai"

  class << self
    attr_writer :backend

    def backend
      @backend ||= OpenSourceBackend.new
    end

    # Restore the open-source default. For tests that swap the backend.
    def reset_backend!
      @backend = OpenSourceBackend.new
    end

    def check(workspace, feature)
      backend.check(workspace, feature)
    end

    def allows?(workspace, feature)
      check(workspace, feature).allowed?
    end

    def allow
      Result.new(true, nil)
    end

    def deny(message)
      Result.new(false, message)
    end
  end
end
