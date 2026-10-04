require "test_helper"

module Integrations
  class DigitaloceanApiTest < ActiveSupport::TestCase
    setup do
      @api = DigitaloceanApi.new("dop-token")
    end

    test "a list follows DigitalOcean's next page link, with the token, until there is none, and says when it stopped short" do
      Http.expects(:request).twice.with do |uri, request, **|
        uri.path == "/v2/apps" && request["Authorization"] == "Bearer dop-token" && URI.decode_www_form(uri.query).include?([ "per_page", "200" ])
      end.returns(response(200, { apps: [ { id: "a" } ], links: { pages: { next: "https://api.digitalocean.com/v2/apps?page=2" } } }),
                  response(200, { apps: [ { id: "b" } ], links: {} }))

      listed = @api.apps
      assert_equal %w[a b], listed.items.map { |app| app["id"] }
      assert_not listed.incomplete?

      Http.stubs(:request).returns(response(200, { droplets: [ { id: 1 } ], links: { pages: { next: "https://api.digitalocean.com/v2/droplets?page=2" } } }))
      assert @api.droplets.incomplete?
    end

    test "logs are read from the archived files DigitalOcean links to, without sending the token there" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v2/apps/app-1/components/web/logs" && URI.decode_www_form(uri.query).sort == [ %w[follow false], %w[type RUN] ] &&
          request["Authorization"] == "Bearer dop-token"
      end.returns(response(200, { historic_urls: [ "https://logs.example/run.log" ], live_url: "wss://logs.example/live" }))
      Http.expects(:download).with("https://logs.example/run.log", provider_key: DigitaloceanApi::PROVIDER_KEY, error_class: DigitaloceanApi::Error,
                                   limit: DigitaloceanApi::LOG_BYTES).returns("web 2026-10-01T10:00:00Z started\n")

      urls = @api.log_urls("app-1", type: "RUN", component: "web")

      assert_equal [ "https://logs.example/run.log" ], urls
      assert_equal "web 2026-10-01T10:00:00Z started\n", @api.log_file(urls.first)
    end

    test "a change is sent as JSON, and DigitalOcean's refusal is raised with its own reason" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v2/apps/app-1/rollback" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "deployment_id" => "dep-1" }
      end.returns(response(403, { id: "forbidden", message: "You do not have access for the attempted action." }))

      error = assert_raises(DigitaloceanApi::Error) { @api.rollback("app-1", "dep-1") }

      assert_equal "DigitalOcean answered 403: You do not have access for the attempted action.", error.message
    end

    test "being asked to slow down is its own error, so a sweep stops" do
      Http.stubs(:request).returns(response(429, { id: "too_many_requests", message: "API Rate limit exceeded." }))

      error = assert_raises(DigitaloceanApi::Error) { @api.droplets }
      assert_kind_of Integrations::RateLimited, error
    end

    test "metrics come back as DigitalOcean's series" do
      Http.expects(:request).with do |uri, **|
        uri.path == "/v2/monitoring/metrics/apps/cpu_percentage" && URI.decode_www_form(uri.query).include?(%w[app_id app-1])
      end.returns(response(200, { status: "success", data: { resultType: "matrix", result: [ { metric: { app_component: "web" }, values: [ [ 1, "5" ] ] } ] } }))

      assert_equal [ { "metric" => { "app_component" => "web" }, "values" => [ [ 1, "5" ] ] } ],
                   @api.metrics("apps/cpu_percentage", "app_id" => "app-1", "start" => 1, "end" => 2)
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
