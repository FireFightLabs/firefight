class AdapterError < StandardError
  class TriggerExpired < AdapterError; end
  class ChannelExists < AdapterError; end
end
