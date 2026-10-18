class WriteSearchEmbeddingJob < ApplicationJob
  queue_as :default

  # Two writes of one record wait for each other, so the second finds the first's vector rather than paying for it again.
  # A write is one embedding call under the model's request timeout, so the wait outlasts any write.
  limits_concurrency key: ->(record_type, record_id) { "#{record_type}:#{record_id}" }, duration: 15.minutes

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(record_type, record_id)
    record = record_type.constantize.find(record_id)
    return unless Entitlements.allows?(record.workspace, Entitlements::AI)

    SearchEmbeddingService.new(record.workspace).write!(record)
  end
end
