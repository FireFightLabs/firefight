class AdapterError < StandardError
  class TriggerExpired < AdapterError; end
end
