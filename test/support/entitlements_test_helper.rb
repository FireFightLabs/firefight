module EntitlementsTestHelper
  extend ActiveSupport::Concern

  included do
    teardown { Entitlements.reset_backend! }
  end

  # Denies features while still letting the workspace in, the way a lapsed trial loses AI but keeps its data.
  DenyingBackend = Struct.new(:message) do
    def check(_workspace, feature)
      feature == Entitlements::ACCESS ? Entitlements.allow : Entitlements.deny(message)
    end
  end

  # Keeps the workspace out altogether, as a hosted build does once a subscription has lapsed.
  AccessBlockingBackend = Struct.new(:message, :path) do
    def check(_workspace, feature)
      feature == Entitlements::ACCESS ? Entitlements.deny(message, path: path) : Entitlements.allow
    end
  end

  # Allows everything and names where a new workspace goes next, as a hosted build's plan picker does.
  NextStepBackend = Struct.new(:path) do
    def check(_workspace, _feature) = Entitlements.allow
    def next_step_path(_workspace) = path
  end

  def deny_entitlements!(message = "Your trial has ended.")
    Entitlements.backend = DenyingBackend.new(message)
    message
  end

  def block_access!(message = "This workspace has no plan.", path: nil)
    Entitlements.backend = AccessBlockingBackend.new(message, path)
    message
  end

  def send_new_workspaces_to!(path)
    Entitlements.backend = NextStepBackend.new(path)
  end
end
