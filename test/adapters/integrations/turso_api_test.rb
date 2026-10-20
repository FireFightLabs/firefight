require "test_helper"

module Integrations
  class TursoApiTest < ActiveSupport::TestCase
    setup do
      @api = TursoApi.new("Bearer token-1")
    end

    test "organizations and a database's usage are read with the token as it is held, the period in the query" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.turso.tech/v1/organizations" && request["Authorization"] == "Bearer token-1"
      end.returns(response(200, [ { slug: "acme", name: "Acme" } ]))
      assert_equal [ { "slug" => "acme", "name" => "Acme" } ], @api.organizations

      Http.expects(:request).with do |uri, _request, **|
        uri.path == "/v1/organizations/acme/databases/shop/usage" && URI.decode_www_form(uri.query).to_h == { "from" => "2026-10-01T00:00:00Z" }
      end.returns(response(200, { database: { total: { rows_read: 10 } } }))
      assert_equal({ "total" => { "rows_read" => 10 } }, @api.usage("acme", "shop", from: "2026-10-01T00:00:00Z"))
    end

    test "a token the API does not take and a database that is not there are told apart" do
      Http.expects(:request).returns(response(401, { error: "invalid token" }))
      assert_raises(TursoApi::Refused) { @api.organizations }
      Http.expects(:request).returns(response(404, { error: "database not found" }))
      assert_raises(TursoApi::NotFound) { @api.usage("acme", "shop") }
    end

    private

    def response(code, body) = stub(code: code.to_s, body: body.to_json, each_header: [].each, to_hash: {})
  end
end
