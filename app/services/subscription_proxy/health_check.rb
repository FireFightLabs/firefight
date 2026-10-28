module SubscriptionProxy
  # Asks the subscription proxy whether it is up and runs with the settings that keep each workspace to its own
  # subscriptions, and records the answer on SubscriptionProxy::Check. While it fails Firefight sends the proxy nothing.
  class HealthCheck
    # The settings the isolation test (script/subscription_proxy_isolation.rb) proved, read back from the running proxy.
    REQUIRED = { "force-model-prefix" => true, "session-affinity" => true }.freeze

    def self.run
      return unless SubscriptionProxy.configured?

      client = Client.new
      version = client.health
      routing = client.settings.fetch("routing", {})
      wrong = REQUIRED.reject { |setting, value| routing[setting] == value }.keys
      if wrong.any?
        Check.failed!("runs without #{wrong.to_sentence}, which keep workspaces apart")
      else
        Check.passed!(version: version)
      end
    rescue Error => error
      Check.failed!(error.message)
    end
  end
end
