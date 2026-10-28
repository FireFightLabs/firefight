module SubscriptionProxy
  # Asks the subscription proxy whether it is up and runs with the settings that keep each workspace to its own
  # subscriptions, and records the answer on SubscriptionProxy::Check. While it fails Firefight sends the proxy nothing.
  class HealthCheck
    # The settings the isolation test (script/subscription_proxy_isolation.rb) proved, read back from the running proxy.
    REQUIRED = { "force-model-prefix" => true, "session-affinity" => true }.freeze
    NO_HOOK = "runs without Firefight's sign-in hook, so its sign-ins would be saved with no workspace".freeze
    # A sign-in id no sign-in has, which the hook answers with nothing and a proxy without it does not know.
    PROBE = "00000000-0000-4000-8000-000000000000".freeze

    def self.run
      return unless SubscriptionProxy.configured?

      client = Client.new
      version = client.health
      routing = client.settings.fetch("routing", {})
      wrong = REQUIRED.reject { |setting, value| routing[setting] == value }.keys
      return Check.failed!("runs without #{wrong.to_sentence}, which keep workspaces apart") if wrong.any?
      return Check.failed!(NO_HOOK) unless hooked?(client)

      Check.passed!(version: version)
    rescue Error => error
      Check.failed!(error.message)
    end

    def self.hooked?(client)
      client.sign_in_result(PROBE)
      true
    rescue NotFound
      false
    end
    private_class_method :hooked?
  end
end
