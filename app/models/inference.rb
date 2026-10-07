class Inference < ApplicationRecord
  STATUS_SUCCESS = "success"
  STATUS_ERROR   = "error"

  # The provider refused because the account paying for the model has no credit left. Kept on refusals a smaller retry
  # then answered too, so a balance running low shows before calls start failing.
  ERROR_OUT_OF_CREDIT = "out_of_credit"

  # Who paid for the call.
  PAID_BY_ACCOUNT = "workspace_account"
  PAID_BY_CREDITS = "firefight_credits"
  PAID_BY_OPERATOR = "operator"
  PAID_BY_FIREFIGHT = "firefight"
  PAYERS = [ PAID_BY_ACCOUNT, PAID_BY_CREDITS, PAID_BY_OPERATOR, PAID_BY_FIREFIGHT ].freeze

  CONTEXT_KEYS = %i[
    workspace feature provider model inferable member api_key prompt_template prompt_version max_output_tokens
    paid_by workspace_ai_account
  ].freeze

  belongs_to :workspace
  belongs_to :workspace_ai_account, optional: true
  belongs_to :member, class_name: "WorkspaceMembership", optional: true
  belongs_to :api_key, optional: true
  belongs_to :inferable, polymorphic: true, optional: true

  validates :feature, :provider, :model, :status, presence: true
  validates :paid_by, inclusion: { in: PAYERS }

  before_validation :default_payer

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
      inference.payer.answered!(inference.provider)
      AiSpend.record!(inference)
      [ response, inference ]
    rescue StandardError => e
      create!(
        **attrs,
        latency_ms:  elapsed_ms_since(started),
        status:      STATUS_ERROR,
        error_class: e.class.name,
        error_kind:  (ERROR_OUT_OF_CREDIT if FirefightAi::Credit.from(e).out_of_credit?)
      )
      raise
    end
  end

  def payer = AiPayer.new(paid_by: paid_by, account: workspace_ai_account)

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

  private

  # A call no workspace chose a payer for runs on the deployment's own account, as every call did before workspaces
  # could bring their own.
  def default_payer
    self.paid_by ||= AiPayer.deployment(workspace).paid_by if workspace
  end
end
