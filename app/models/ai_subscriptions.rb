# The AI subscriptions a workspace can connect through the subscription proxy, from config/ai_subscriptions.yml. Each
# signs in the way its provider's own command line tool does, through the proxy, which keeps the sign-in.
module AiSubscriptions
  REGISTRY_PATH = Rails.root.join("config/ai_subscriptions.yml")

  # The person enters a code the proxy shows on the provider's page, and the proxy hears when they are done.
  SIGN_IN_DEVICE = "device".freeze
  # The provider sends the browser to an address on the person's own computer, which they paste back.
  SIGN_IN_PASTE = "paste".freeze
  SIGN_INS = [ SIGN_IN_DEVICE, SIGN_IN_PASTE ].freeze

  Site = Data.define(:proxy, :label)

  Subscription = Data.define(:key, :name, :plan, :sign_in, :sites, :main_models, :fast_models) do
    def device? = sign_in == SIGN_IN_DEVICE

    def site(proxy) = sites.find { |site| site.proxy == proxy.to_s }

    # The proxy's sign-ins this subscription's credentials come from.
    def proxies = sites.map(&:proxy)

    # The first of the recommended models for the role the workspace's sign-ins serve, else the first it serves.
    def recommended(role, available)
      wanted = role.to_s == WorkspaceAiAccount::FAST ? fast_models : main_models
      wanted.find { |model| available.include?(model) } || available.first
    end
  end

  def self.all = registry.values

  def self.find(key) = registry[key.to_s]

  # The subscription a sign-in at the proxy belongs to.
  def self.for_proxy(proxy) = all.find { |subscription| subscription.proxies.include?(proxy.to_s) }

  # Offered only where the proxy is configured.
  def self.offered = SubscriptionProxy.configured? ? all : []

  def self.registry
    @registry ||= YAML.load_file(REGISTRY_PATH).to_h do |key, entry|
      raise ArgumentError, "#{key} signs in by #{entry['sign_in'].inspect}" unless SIGN_INS.include?(entry.fetch("sign_in"))

      sites = entry.fetch("sites").map { |site| Site.new(proxy: site.fetch("proxy"), label: site["label"]) }.freeze
      [ key, Subscription.new(key: key, name: entry.fetch("name"), plan: entry.fetch("plan"), sign_in: entry.fetch("sign_in"), sites: sites,
                              main_models: entry.fetch("main").freeze, fast_models: entry.fetch("fast").freeze) ]
    end.freeze
  end
  private_class_method :registry
end
