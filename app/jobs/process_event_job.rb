class ProcessEventJob < ApplicationJob
  queue_as :events

  def perform(platform, payload)
    EventDispatcher.dispatch(platform, payload)
  end
end
