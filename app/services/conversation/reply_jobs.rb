# What the queue knows about a conversation's reply jobs. Each carries the conversation's concurrency key, the lock that
# lets one turn run at a time, so the key finds every one of them.
class Conversation::ReplyJobs
  def self.key(conversation) = ConversationReplyJob.new(conversation.id).concurrency_key

  # Queued, waiting behind the lock, or claimed by a worker. A worker that died keeps its claim until the queue prunes it,
  # and then the job is failed.
  def self.waiting_or_running?(conversation)
    SolidQueue::Job.where(concurrency_key: key(conversation), finished_at: nil).where.missing(:failed_execution).exists?
  end

  # The newest failure of a reply job since the turn began, or nil.
  def self.last_failed(conversation, since:)
    SolidQueue::FailedExecution.joins(:job).where(solid_queue_jobs: { concurrency_key: key(conversation) })
      .where(created_at: since..).order(:created_at).last
  end

  # The same job again, with the same asker and the same held call.
  def self.retry!(failed) = failed.retry
end
