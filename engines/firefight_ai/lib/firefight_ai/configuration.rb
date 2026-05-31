module FirefightAi
  class Configuration
    attr_accessor :default_model, :anthropic_api_key, :request_timeout

    def initialize
      @default_model = "claude-sonnet-4-6"
      @anthropic_api_key = nil
      @request_timeout = 120
    end
  end
end
