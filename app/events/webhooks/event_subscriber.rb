class Webhooks::EventSubscriber
  def self.handle(event)
    Webhooks::DispatchJob.perform_later(event.to_h)
  end
end
