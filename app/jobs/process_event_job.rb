class ProcessEventJob < ApplicationJob
  queue_as :events

  # Slack already 200-ack'd the webhook before this job runs, so a transient
  # DB hiccup that kills the job here loses the event entirely (Slack won't
  # redeliver). Polynomial backoff covers ConnectionNotEstablished beyond the
  # Deadlocked retry inherited from ApplicationJob.
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 3

  def perform(platform, payload)
    EventDispatcher.dispatch(platform, payload)
  end
end
