module Entitlements
  # path is where a person goes to lift the block, such as a billing page, when the backend has one.
  Result = Struct.new(:allowed, :message, :path) do
    def allowed?
      allowed
    end

    def blocked?
      !allowed
    end
  end
end
