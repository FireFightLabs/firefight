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

    test "a site's hooks are listed, made, turned on and deleted at the paths the spec gives, and not found and a refusal are told apart" do
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/hooks" && URI.decode_www_form(uri.query).to_h == { "site_id" => "s1" } && request.is_a?(Net::HTTP::Get) }
          .returns(response(200, [ { id: "h1", type: "url", event: "deploy_created", data: { url: "https://ff.example/hook" } } ]))
      assert_equal [ "h1" ], @api.hooks("s1").map { |hook| hook["id"] }

      Http.expects(:request).with do |uri, request, **|
        uri.path == "/api/v1/hooks" && URI.decode_www_form(uri.query).to_h == { "site_id" => "s1" } && request.is_a?(Net::HTTP::Post) &&
          JSON.parse(request.body) == { "type" => "url", "event" => "deploy_created", "data" => { "url" => "https://ff.example/hook", "signature_secret" => "s3cret" } }
      end.returns(response(201, { id: "h2" }))
      assert_equal "h2", @api.create_hook("s1", event: "deploy_created", url: "https://ff.example/hook", secret: "s3cret")["id"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/hooks/types" && URI.decode_www_form(uri.query).to_h == { "site_id" => "s1" } && request.is_a?(Net::HTTP::Get) }
          .returns(response(200, [ { name: "url", events: [ "deploy_created" ] } ]))
      assert_equal "url", @api.hook_types("s1").sole["name"]

      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/hooks/h2/enable" && request.is_a?(Net::HTTP::Post) }.returns(response(200, { id: "h2" }))
      @api.enable_hook("h2")
      Http.expects(:request).with { |uri, request, **| uri.path == "/api/v1/hooks/h2" && request.is_a?(Net::HTTP::Delete) }.returns(stub(code: "204", body: ""))
      assert_equal({}, @api.delete_hook("h2"))

      Http.stubs(:request).returns(response(404, { code: 404, message: "Not Found" }))
      assert_raises(NetlifyApi::NotFound) { @api.site("s9") }
      Http.stubs(:request).returns(response(422, { code: 422, message: "Validation failed" }))
      assert_raises(NetlifyApi::Refused) { @api.create_hook("s1", event: "deploy_created", url: "https://ff.example/hook", secret: "s3cret") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
