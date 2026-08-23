module Events
  class PinRemovedHandler
    def self.execute(workspace, payload)
      Events::PinAddedHandler.handle(workspace, payload, IncidentEvent::MESSAGE_UNPINNED)
    end
  end
end
