# The subscription proxy Firefight runs beside itself (deploy/subscription-proxy, docs/ai.md, Subscriptions). It holds
# the sign-ins to workspaces' AI subscriptions and answers model calls made with them. Firefight keeps no token of
# its own, only the name the proxy gives each sign-in, and every sign-in carries its workspace's id as its prefix, so
# a call names the one workspace whose subscriptions may answer it.
module SubscriptionProxy
  Error = Class.new(StandardError)
  NotConfigured = Class.new(Error)
  # The proxy did not answer, or not in time.
  Unreachable = Class.new(Error)
  # The proxy answered with a refusal. status is its HTTP status.
  class Refused < Error
    attr_reader :status

    def initialize(message, status:)
      super(message)
      @status = status
    end
  end

  # Where failed calls to it are kept, beside the chat platform's (PlatformCallFailure).
  PLATFORM = "subscription_proxy".freeze

  # The proxy answers in the OpenAI shape under this path.
  INFERENCE_PATH = "/v1".freeze

  def self.settings = Rails.configuration.x.subscription_proxy

  def self.configured? = settings.url.present? && settings.client_key.present? && settings.management_key.present?

  # Configured and its last check found it up with its workspaces kept apart.
  def self.usable? = configured? && Check.passing?

  def self.url = settings.url.to_s.chomp("/")

  def self.inference_base = "#{url}#{INFERENCE_PATH}"

  def self.prefix_for(workspace) = workspace.id.to_s

  # The model as the proxy names it for one workspace, which only that workspace's sign-ins serve.
  def self.model_for(workspace, model) = "#{prefix_for(workspace)}/#{model}"

  # The model's own name, without the workspace's prefix.
  def self.unprefixed(workspace, model)
    model.to_s.delete_prefix("#{prefix_for(workspace)}/")
  end
end
