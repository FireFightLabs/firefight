class AdapterError < StandardError
  class TriggerExpired < AdapterError; end
  class ChannelExists < AdapterError; end
  class AlreadyArchived < AdapterError; end
  class NotFound < AdapterError; end
  class AlreadyInChannel < AdapterError; end
  class IsArchived < AdapterError; end
  class NotInChannel < AdapterError; end
  class RestrictedAction < AdapterError; end
  class UnsafeDownloadHost < AdapterError; end

  class AuthRevoked < AdapterError
    attr_reader :error_code

    def initialize(error_code)
      @error_code = error_code
      super("Platform auth revoked: #{error_code}")
    end
  end

  class RateLimited < AdapterError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super("Rate-limited; retry_after=#{retry_after}s")
    end
  end
end
