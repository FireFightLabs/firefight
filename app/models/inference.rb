class Inference < ApplicationRecord
  STATUS_SUCCESS = "success"
  STATUS_ERROR   = "error"

  CONTEXT_KEYS = %i[workspace feature provider model inferable member api_key].freeze

  belongs_to :workspace
  belongs_to :member, class_name: "WorkspaceMembership", optional: true
  belongs_to :api_key, optional: true
  belongs_to :inferable, polymorphic: true, optional: true

  validates :feature, :provider, :model, :status, presence: true

  def self.track(context)
    attrs   = context.slice(*CONTEXT_KEYS)
    started = monotonic_now

    begin
      response = yield
      inference = create!(
        **attrs,
        input_tokens:        response.try(:input_tokens).to_i,
        output_tokens:       response.try(:output_tokens).to_i,
        cache_read_tokens:   response.try(:cache_read_tokens).to_i,
        cache_write_tokens:  response.try(:cache_write_tokens).to_i,
        cost_micros:         cost_to_micros(response.try(:cost)),
        latency_ms:          elapsed_ms_since(started),
        stop_reason:         response.try(:stop_reason),
        provider_request_id: response.try(:id),
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

  def self.provider_for(model)
    case model
    when /\Agpt-|\Ao\d/ then "openai"
    when /\Aclaude-/   then "anthropic"
    else "unknown"
    end
  end

  def self.cost_to_micros(cost)
    dollars = cost.respond_to?(:total) ? cost.total : cost
    ((dollars || 0).to_f * 1_000_000).round
  end
  private_class_method :cost_to_micros

  def self.monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
  private_class_method :monotonic_now

  def self.elapsed_ms_since(started)
    ((monotonic_now - started) * 1000).round
  end
  private_class_method :elapsed_ms_since
end
