module Events
  class PinRemovedHandler
    def self.execute(platform, payload)
      Events::PinAddedHandler.handle(platform, payload, IncidentEvent::MESSAGE_UNPINNED)
    end
  end
end
