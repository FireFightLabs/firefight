class ProcessEventJob < ApplicationJob
  queue_as :events

  # Slack was already acked and will not redeliver, so a transient DB failure
  # here would lose the event entirely.
  retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 3

  def perform(platform, payload)
    EventDispatcher.dispatch(platform, payload)
  end
end
