module FirefightAi
  # Loads the Faraday adapter model calls go through (Configuration#http_adapter) and answers the name RubyLLM is given.
  # RubyLLM shares one connection per provider, address and adapter across a process's threads, so with a persistent
  # adapter a worker keeps its connections to a provider open between calls rather than opening one per call.
  module HttpAdapter
    LIBRARIES = {
      net_http: "faraday/net_http",
      net_http_persistent: "faraday/net_http_persistent",
      async_http: "async/http/faraday"
    }.freeze

    # A process running on fibers names async_http, whose gem comes with the fiber runtime it runs on.
    def self.load!(adapter)
      require LIBRARIES.fetch(adapter)
      adapter
    rescue LoadError => e
      raise LoadError, "FIREFIGHT_AI_HTTP_ADAPTER is #{adapter}, whose library is not installed (#{e.message}). Add its gem to the Gemfile."
    end
  end
end
