module FirefightAi
  class Configuration
    attr_accessor :default_model, :anthropic_api_key

    def initialize
      @default_model = "claude-sonnet-4-6"
      @anthropic_api_key = nil
    end
  end
end
