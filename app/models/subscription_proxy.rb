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

  # The proxy does not hold what was named, such as a credential removed there.
  NotFound = Class.new(Refused)

  # Said where a subscription cannot be connected because the proxy is down or does not keep workspaces apart.
  UNAVAILABLE = "Subscriptions cannot be connected right now. Try again in a few minutes.".freeze

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

  # A call without it would reach only sign-ins no workspace has claimed yet, so there is never a call without it.
  def self.prefix_for(workspace)
    prefix = workspace&.id.to_s
    raise ArgumentError, "a subscription call needs its workspace" if prefix.blank?

    prefix
  end

  # The model as the proxy names it for one workspace, which only that workspace's sign-ins serve.
  def self.model_for(workspace, model) = "#{prefix_for(workspace)}/#{model}"

  # How the proxy says every sign-in of a subscription that serves the model is at its limit, once RubyLLM read it.
  LIMIT_REASON = "RateLimitError".freeze

  def self.limited?(error)
    error.class.name.demodulize == LIMIT_REASON || (error.is_a?(FirefightAi::Error) && error.reason == LIMIT_REASON)
  end

  # The call failed on a workspace's subscription because it reached its usage limit.
  def self.limit_reached?(choice, error) = choice.payer&.account&.subscription? == true && limited?(error)

  # "in about 2 hours", for when a limit resets, said the same wherever the person reads it.
  def self.from_now(time)
    minutes = [ ((time - Time.current) / 60).ceil, 1 ].max
    return "in about #{minutes} #{'minute'.pluralize(minutes)}" if minutes < 60

    hours = (minutes / 60.0).round
    return "in about #{hours} #{'hour'.pluralize(hours)}" if hours < 48

    days = (hours / 24.0).round
    "in about #{days} days"
  end

  # The model's own name, without the workspace's prefix.
  def self.unprefixed(workspace, model)
    model.to_s.delete_prefix("#{prefix_for(workspace)}/")
  end
end
