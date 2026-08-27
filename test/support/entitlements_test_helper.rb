module EntitlementsTestHelper
  extend ActiveSupport::Concern

  included do
    teardown { Entitlements.reset_backend! }
  end

  DenyingBackend = Struct.new(:message) do
    def check(_workspace, _feature)
      Entitlements.deny(message)
    end
  end

  def deny_entitlements!(message = "Your trial has ended.")
    Entitlements.backend = DenyingBackend.new(message)
    message
  end
end
