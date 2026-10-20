require "test_helper"

module Integrations
  class UpstashApiTest < ActiveSupport::TestCase
    setup do
      @api = UpstashApi.new("ops@example.com", "key-123")
    end

    test "backups are listed with the key sent as Basic email and key" do
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://api.upstash.com/v2/redis/list-backup/db-1" && request.is_a?(Net::HTTP::Get) &&
          request["Authorization"] == "Basic #{Base64.strict_encode64('ops@example.com:key-123')}"
      end.returns(response(200, [ { backup_id: "bk-1", state: "completed" } ]))

      assert_equal [ { "backup_id" => "bk-1", "state" => "completed" } ], @api.backups("db-1")
    end

    test "a restore posts the backup's id, and a refused key and a missing database are told apart" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/v2/redis/restore-backup/db-1" && request.is_a?(Net::HTTP::Post) && JSON.parse(request.body) == { "backup_id" => "bk-1" }
      end.returns(response(200, "OK"))
      @api.restore_backup("db-1", "bk-1")

      Http.expects(:request).returns(response(401, { error: "Unauthorized" }))
      assert_raises(UpstashApi::Refused) { @api.backups("db-1") }
      Http.expects(:request).returns(response(404, { error: "database not found" }))
      assert_raises(UpstashApi::NotFound) { @api.backups("db-1") }
    end

    private

    def response(code, body) = stub(code: code.to_s, body: body.to_json, each_header: [].each, to_hash: {})
  end
end
