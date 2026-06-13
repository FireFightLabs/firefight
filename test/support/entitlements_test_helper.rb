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

  # Swap in a backend that denies every feature with `message`, simulating the
  # Cloud engine's trial-ended / credits-exhausted state. Reset in teardown.
  def deny_entitlements!(message = "Your trial has ended.")
    Entitlements.backend = DenyingBackend.new(message)
    message
  end
end
