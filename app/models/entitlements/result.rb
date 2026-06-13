module Entitlements
  # Outcome of an entitlement check. On a denial, `message` is user-facing copy
  # supplied by the backend (e.g. "Your trial has ended — upgrade to keep using
  # AI."). The open-source backend never denies, so it is always nil there.
  Result = Struct.new(:allowed, :message) do
    def allowed?
      allowed
    end

    def blocked?
      !allowed
    end
  end
end
