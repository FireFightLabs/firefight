require "test_helper"

module Integrations
  class NetlifyApiTest < ActiveSupport::TestCase
    setup do
      @api = NetlifyApi.new("nfp-token")
    end

    test "every site is read a page at a time with the token, and a full last page reads the next" do
      pages = []
      Http.expects(:request).twice.with do |uri, request, **|
        query = URI.decode_www_form(uri.query).to_h
        pages << query["page"]
        uri.path == "/api/v1/sites" && request["Authorization"] == "Bearer nfp-token" && query["filter"] == "all" && query["per_page"] == "100"
      end.returns(response(200, Array.new(100) { |index| { id: "site-#{index}" } })).then.returns(response(200, [ { id: "last" } ]))

      read = @api.sites

      assert_equal 101, read.items.size
      assert read.complete
      assert_equal %w[1 2], pages
    end

    test "a site's deploys are asked with the swagger's filters, leaving out the ones not given" do
      Http.expects(:request).with do |uri, _request, **|
        query = URI.decode_www_form(uri.query).to_h
        uri.path == "/api/v1/sites/site%201/deploys" && query == { "per_page" => "5", "page" => "1", "production" => "true" }
      end.returns(response(200, [ { id: "d1" } ]))

      assert_equal [ { "id" => "d1" } ], @api.deploys("site 1", limit: 5, production: true)
    end

    test "a restore posts to the deploy's restore path" do
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/sites/s1/deploys/d1/restore" && request.is_a?(Net::HTTP::Post) }
          .returns(response(201, { id: "d1", state: "ready" }))

      assert_equal "ready", @api.restore("s1", "d1")["state"]
    end

    test "Netlify's refusal is raised with its own reason, and being asked to slow down is its own error" do
      Http.stubs(:request).returns(response(401, { code: 401, message: "Access Denied" }))
      assert_equal "Netlify answered 401: Access Denied", assert_raises(NetlifyApi::Error) { @api.user }.message

      Http.stubs(:request).returns(response(429, { message: "Rate limit exceeded" }))
      assert_raises(Integrations::RateLimited) { @api.user }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
