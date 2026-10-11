# Answers RubyLLM's real requests with a provider's own answer, so everything RubyLLM does with it runs as it would in
# production: rendering the request, its error classes, usage and cost. Nothing leaves the test.
module FakeProviderHelper
  # A Faraday adapter that answers with whatever the test queued, and keeps each request it was sent.
  class Adapter < Faraday::Adapter
    Answer = Data.define(:status, :body, :headers)

    class << self
      def answers = (Thread.current[:fake_provider_answers] ||= [])

      def requests = (Thread.current[:fake_provider_requests] ||= [])

      def reset!
        answers.clear
        requests.clear
      end
    end

    def call(env)
      super
      self.class.requests << { url: env.url.to_s, body: env.request_body.is_a?(String) ? JSON.parse(env.request_body) : env.request_body }
      answer = self.class.answers.shift || raise("The test queued no answer for #{env.url}")
      save_response(env, answer.status, answer.body.is_a?(String) ? answer.body : answer.body.to_json,
                    { "content-type" => "application/json" }.merge(answer.headers))
      @app.call(env)
    end
  end

  NAME = :firefight_fake_provider
  Faraday::Adapter.register_middleware(NAME => Adapter)

  # A context whose calls go to Adapter, with a made up key for each provider named.
  def fake_provider_context(**settings)
    RubyLLM.context do |config|
      settings.each { |name, value| config.public_send("#{name}=", value) }
      config.faraday_adapter = NAME
      config.max_retries = 0
    end
  end

  def answer_with(body, status: 200, headers: {})
    Adapter.answers << Adapter::Answer.new(status: status, body: body, headers: headers)
  end

  def sent_requests = Adapter.requests

  # The error RubyLLM raises for the provider's answer, as a model call on it would meet it.
  def provider_error(provider, model, status:, body:, headers: {}, **settings)
    Adapter.reset!
    answer_with(body, status: status, headers: headers)
    fake_provider_context(**settings).chat(model: model, provider: provider, assume_model_exists: true).ask("Hello")
    flunk "#{provider} answered #{status} and RubyLLM raised nothing"
  rescue RubyLLM::Error => e
    e
  end
end
