require "test_helper"

module Integrations
  module ReadGuards
    class NorthflankTest < ActiveSupport::TestCase
      test "only a GET passes" do
        assert_equal({ "method" => "get", "path" => "services/web" }, Northflank.reading("api_request", "method" => "get", "path" => "services/web"))

        %w[POST PATCH PUT DELETE].each do |method|
          assert_raises(Refused) { Northflank.reading("api_request", "method" => method, "path" => "services/web/restart") }
        end
      end
    end
  end
end
