class Inference < ApplicationRecord
  STATUS_SUCCESS = "success"
  STATUS_ERROR   = "error"

  CONTEXT_KEYS = %i[
    workspace feature provider model inferable member api_key prompt_template prompt_version
  ].freeze

  belongs_to :workspace
  belongs_to :member, class_name: "WorkspaceMembership", optional: true
  belongs_to :api_key, optional: true
  belongs_to :inferable, polymorphic: true, optional: true

  validates :feature, :provider, :model, :status, presence: true

  def self.track(context)
    attrs   = context.slice(*CONTEXT_KEYS)
    started = monotonic_now
    PromptVersion.remember!(
      template: context[:prompt_template], version: context[:prompt_version], text: context[:prompt_text]
    )

    begin
      response = yield
      tokens = response.try(:tokens)
      inference = create!(
        **attrs,
        input_tokens:        tokens.try(:input).to_i,
        output_tokens:       tokens.try(:output).to_i,
        cache_read_tokens:   tokens.try(:cache_read).to_i,
        cache_write_tokens:  tokens.try(:cache_write).to_i,
        cost_micros:         cost_to_micros(response.try(:cost)),
        latency_ms:          elapsed_ms_since(started),
        stop_reason:         response.try(:finish_reason)&.to_s,
        provider_request_id: provider_request_id(response),
        status:              STATUS_SUCCESS
      )
      [ response, inference ]
    rescue StandardError => e
      create!(
        **attrs,
        latency_ms:  elapsed_ms_since(started),
        status:      STATUS_ERROR,
        error_class: e.class.name
      )
      raise
    end
  end

  # An explicit provider wins, for a model the registry does not know.
  def self.provider_for(model, provider: nil)
    return provider.to_s if provider.present?

    RubyLLM.models.find(model).provider.to_s
  rescue RubyLLM::ModelNotFoundError
    "unknown"
  end

  def self.cost_to_micros(cost)
    dollars = cost.respond_to?(:total) ? cost.total : cost
    ((dollars || 0).to_f * 1_000_000).round
  end
  private_class_method :cost_to_micros

  # The provider's own id for the call, read off the raw body since RubyLLM does not surface it.
  def self.provider_request_id(response)
    body = response.try(:raw).try(:body)
    body["id"].presence if body.is_a?(Hash)
  end
  private_class_method :provider_request_id

  def self.monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  private_class_method :monotonic_now

  def self.elapsed_ms_since(started)
    ((monotonic_now - started) * 1000).round
  end
  private_class_method :elapsed_ms_since
end
