require "test_helper"

module Integrations
  class VercelApiTest < ActiveSupport::TestCase
    test "a team given by id is sent as teamId, by slug as slug, and a token made for one team names none" do
      seen = []
      Http.stubs(:request).with { |uri, request, **| seen << [ URI.decode_www_form(uri.query.to_s).to_h, request["Authorization"] ] }.returns(response(200, []))

      VercelApi.new("tok", "team_abc").check!
      VercelApi.new("tok", "acme").check!
      VercelApi.new("tok", " ").check!

      assert_equal [ { "limit" => "1", "teamId" => "team_abc" }, { "limit" => "1", "slug" => "acme" }, { "limit" => "1" } ], seen.map(&:first)
      assert seen.all? { |_, header| header == "Bearer tok" }
    end

    test "projects are read in every list shape Vercel answers, page by page from the continuation" do
      page = Array.new(VercelApi::PAGE_SIZE) { |index| { id: "prj_#{index}" } }
      Http.expects(:request).with { |uri, *| !uri.query.include?("from") }.returns(response(200, { projects: page, pagination: { count: 100, next: "abc" } }))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).include?([ "from", "abc" ]) }.returns(response(200, [ { id: "prj_last" } ]))

      assert_equal VercelApi::PAGE_SIZE + 1, VercelApi.new("tok").projects.items.size
    end

    test "a rollback the plan refuses is its own error, in Vercel's words, and a promotion says whether it was queued" do
      Http.stubs(:request).returns(response(402, { error: { code: "payment_required", message: "Upgrade to Pro" } }))
      error = assert_raises(VercelApi::PlanLimited) { VercelApi.new("tok").rollback("prj_1", "dpl_1", description: "bad deploy") }
      assert_equal "Vercel answered 402: Upgrade to Pro", error.message

      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v10/projects/prj_1/promote/dpl_2" && request.is_a?(Net::HTTP::Post) && request.body == "{}"
      end.returns(stub(code: "202", body: ""))
      assert_equal 202, VercelApi.new("tok").promote("prj_1", "dpl_2").status

      Http.stubs(:request).returns(response(429, { error: { code: "rate_limited", message: "Too many requests" } }))
      assert_raises(Integrations::RateLimited) { VercelApi.new("tok").project("web") }
    end

    test "runtime logs are read from the live stream until it ends, and only whole rows count" do
      rows = [ { rowId: "1", level: "error", message: "boom", source: "serverless", timestampInMs: 1_790_000_000_000 },
               { rowId: "", level: "error", message: "limit", source: "delimiter", timestampInMs: 1_790_000_001_000 },
               { rowId: "3", level: "info", message: "after", source: "serverless", timestampInMs: 1_790_000_002_000 } ]
      body = rows.map(&:to_json).join("\n") + "\n"
      response = Object.new
      response.define_singleton_method(:code) { "200" }
      response.define_singleton_method(:read_body) { |&block| [ body[0, 20], body[20..] ].each { |chunk| block.call(chunk) } }
      connection = Object.new
      connection.define_singleton_method(:request) { |_request, &block| block.call(response) }
      Net::HTTP.expects(:start).with("api.vercel.com", 443, has_entries(use_ssl: true, read_timeout: 10)).yields(connection)

      found = VercelApi.new("tok").runtime_logs("prj_1", "dpl_1", seconds: 10, limit: 50)

      assert_equal [ "boom" ], found.map { |row| row["message"] }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
