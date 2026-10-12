require "test_helper"
require "open3"

class ErrorReportingTest < ActiveSupport::TestCase
  DSN = "https://public@sentry.invalid/1".freeze
  SECRETS = {
    path: "pathS3cret",
    authorization: "b3arerToken",
    cookie: "c00kieValue",
    api_key: "apiK3yValue",
    webhook_token: "w3bhookToken",
    query_token: "qu3ryToken",
    form_secret: "f0rmSecret",
    ai_key: "sk-ant-l1veKey",
    credential: "integrationCr3dential"
  }.freeze

  test "an app without SENTRY_DSN loads none of Sentry" do
    skip "SENTRY_DSN is set in this shell" if ENV["SENTRY_DSN"].present?

    assert_nil ErrorReporting.dsn
    assert_empty Rails.application.middleware.map(&:name).grep(/Sentry/)
    assert_empty ActiveJob::Base.ancestors.map(&:to_s).grep(/Sentry/)
  end

  test "an app with SENTRY_DSN boots reporting errors from requests and jobs, and nothing else" do
    script = <<~RUBY
      config = Sentry.configuration
      puts({
        initialized: Sentry.initialized?,
        environment: config.environment,
        release: config.release,
        tracing: config.tracing_enabled?,
        profiling: config.profiling_enabled?,
        sessions: config.session_tracking?,
        middleware: Rails.application.middleware.map(&:name).grep(/Sentry|PathSecret/),
        jobs: ActiveJob::Base.ancestors.include?(Sentry::Rails::ActiveJobExtensions)
      }.to_json)
    RUBY
    env = { "SENTRY_DSN" => DSN, "DEPLOYMENT_ENVIRONMENT" => "staging", "OTEL_SERVICE_VERSION" => "abc1234", "RAILS_ENV" => "test" }

    output, status = Open3.capture2e(env, "bin/rails", "runner", script, chdir: Rails.root.to_s)

    assert status.success?, output
    booted = JSON.parse(output.lines.last)
    assert booted["initialized"]
    assert_equal "staging", booted["environment"]
    assert_equal "abc1234", booted["release"]
    assert_not booted["tracing"]
    assert_not booted["profiling"]
    assert_not booted["sessions"]
    assert_equal [ "PathSecret", "Sentry::Rails::CaptureExceptions", "Sentry::Rails::RescuedExceptionInterceptor" ], booted["middleware"]
    assert booted["jobs"]
  end

  test "release is the version the image was built from, and none for a build without one" do
    with_env("OTEL_SERVICE_VERSION" => "abc1234") { assert_equal "abc1234", ErrorReporting.release }
    with_env("OTEL_SERVICE_VERSION" => "dev") { assert_nil ErrorReporting.release }
    with_env("OTEL_SERVICE_VERSION" => nil) { assert_nil ErrorReporting.release }
  end

  test "environment is the deployment's, else the Rails environment" do
    with_env("DEPLOYMENT_ENVIRONMENT" => "production-eu") { assert_equal "production-eu", ErrorReporting.environment }
    with_env("DEPLOYMENT_ENVIRONMENT" => nil) { assert_equal Rails.env, ErrorReporting.environment }
  end

  test "the browser gets settings only from its own DSN, never the server's" do
    with_env("SENTRY_FRONTEND_DSN" => nil, "SENTRY_DSN" => DSN) { assert_nil ErrorReporting.browser }

    with_env("SENTRY_FRONTEND_DSN" => "https://browser@sentry.invalid/2", "DEPLOYMENT_ENVIRONMENT" => "staging", "OTEL_SERVICE_VERSION" => "abc1234") do
      assert_equal({ dsn: "https://browser@sentry.invalid/2", environment: "staging", release: "abc1234" }, ErrorReporting.browser)
    end
  end

  test "an event from a request carries none of the secrets the request held" do
    event = capture_from_request(through_path_secret: true)
    sent = event.to_json_compatible.to_json

    SECRETS.each_value { |secret| assert_not_includes sent, secret }
    assert_equal "https://firefight.test/api/v1/issue_events/[FILTERED]", event.request.url
    assert_equal "Firefight test", event.request.headers["User-Agent"]
    assert_equal "[FILTERED]", event.request.headers["X-Gitlab-Token"]
    assert_nil event.request.query_string
    assert_nil event.request.data
    assert_empty event.request.cookies
    assert_equal "[FILTERED]", event.extra[:credentials]
  end

  test "a secret in the path is masked even when the event took its request from before the mask" do
    event = capture_from_request(through_path_secret: false)

    assert_equal "https://firefight.test/api/v1/issue_events/[FILTERED]", event.request.url
    assert_not_includes event.to_json_compatible.to_json, SECRETS[:path]
  end

  private

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def capture_from_request(through_path_secret:)
    require "sentry-ruby"
    require "sentry-rails"

    config = Sentry::Configuration.new
    with_env("SENTRY_DSN" => DSN) { ErrorReporting.configure(config) }
    config.transport.transport_class = Sentry::DummyTransport
    config.background_worker_threads = 0
    client = Sentry::Client.new(config)
    hub = Sentry::Hub.new(client, Sentry::Scope.new)

    account = WorkspaceAiAccount.new(credentials: { "api_key" => SECRETS[:ai_key] })
    failing = lambda do |env|
      hub.configure_scope { |scope| scope.set_rack_env(env) }
      hub.capture_exception(RuntimeError.new("Could not reach the provider for #{account.inspect}"),
        extra: { credentials: { "token" => SECRETS[:credential] } }, hint: { background: false })
      [ 500, {}, [] ]
    end
    env = Rack::MockRequest.env_for(
      "https://firefight.test/api/v1/issue_events/#{SECRETS[:path]}?token=#{SECRETS[:query_token]}",
      method: "POST",
      params: { "secret" => SECRETS[:form_secret] },
      "HTTP_AUTHORIZATION" => "Bearer #{SECRETS[:authorization]}",
      "HTTP_COOKIE" => "_firefight_session=#{SECRETS[:cookie]}",
      "HTTP_X_API_KEY" => SECRETS[:api_key],
      "HTTP_X_GITLAB_TOKEN" => SECRETS[:webhook_token],
      "HTTP_USER_AGENT" => "Firefight test"
    )
    through_path_secret ? PathSecret.new(failing).call(env) : failing.call(env)

    client.transport.events.sole
  end
end
