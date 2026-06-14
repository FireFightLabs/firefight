module Entitlements
  Result = Struct.new(:allowed, :message) do
    def allowed?
      allowed
    end

    def blocked?
      !allowed
    end
  end
end
