module FirefightAi
  class Configuration
    attr_accessor :default_model, :openai_api_key, :request_timeout

    def initialize
      @default_model = nil
      @openai_api_key = nil
      @request_timeout = 120
    end
  end
end
