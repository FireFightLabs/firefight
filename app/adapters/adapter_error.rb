class AdapterError < StandardError
  class TriggerExpired < AdapterError; end
  class ChannelExists < AdapterError; end
  class AlreadyArchived < AdapterError; end
  class NotFound < AdapterError; end
end
