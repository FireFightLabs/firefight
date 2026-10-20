require "test_helper"

module Integrations
  class CircleciApiTest < ActiveSupport::TestCase
    test "a workflow's jobs are read page after page, and a list longer than the bound is refused rather than read in part" do
      api = CircleciApi.new("t")
      api.stubs(:get).with(CircleciApi::V3, "/jobs", { "filter[workflow_id]" => "w-1" }).returns({ "data" => [ { "id" => "j-1" } ], "page" => { "next" => "c-2" } })
      api.stubs(:get).with(CircleciApi::V3, "/jobs", { "filter[workflow_id]" => "w-1", "page[cursor]" => "c-2" }).returns({ "data" => [ { "id" => "j-2" } ], "page" => { "next" => nil } })

      assert_equal %w[j-1 j-2], api.jobs("w-1").map { |job| job["id"] }

      api.stubs(:get).with(CircleciApi::V3, "/jobs", has_entry("filter[workflow_id]" => "w-2")).returns({ "data" => [ { "id" => "j" } ], "page" => { "next" => "more" } })
      assert_raises(CircleciApi::Error) { api.jobs("w-2") }
    end
  end
end
