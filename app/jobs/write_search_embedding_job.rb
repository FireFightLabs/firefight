class WriteSearchEmbeddingJob < ApplicationJob
  queue_as :default

  retry_on FirefightAi::TransientError, wait: :polynomially_longer, attempts: 3
  discard_on FirefightAi::TerminalError
  discard_on ActiveRecord::RecordNotFound

  def perform(record_type, record_id)
    record = record_type.constantize.find(record_id)
    return unless Entitlements.allows?(record.workspace, Entitlements::AI)

    SearchEmbeddingService.new(record.workspace).write!(record)
  end
end
