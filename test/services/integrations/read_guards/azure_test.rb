require "test_helper"

module Integrations
  module ReadGuards
    class AzureTest < ActiveSupport::TestCase
      SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze
      VERSION = { "api-version" => "2024-04-01" }.freeze

      test "a GET inside a subscription, or of a resource provider's description, reads with its api-version" do
        read = Azure.reading(ApiReads::TOOL, "path" => "subscriptions/#{SUBSCRIPTION}/resourceGroups/shop", "query" => VERSION)

        assert_equal "/subscriptions/#{SUBSCRIPTION}/resourceGroups/shop", read["path"]
        assert Azure.reads?(ApiReads::TOOL, "path" => "/providers/Microsoft.Web", "query" => VERSION)
        assert_equal SUBSCRIPTION, Azure.subscription_in(read["path"])
        assert_nil Azure.subscription_in("/providers/Microsoft.Web")
      end

      test "a read without an api-version is said, and one outside a subscription is refused by Firefight's rule" do
        assert_raises(Refused) { Azure.reading(ApiReads::TOOL, "path" => "/subscriptions/#{SUBSCRIPTION}") }
        assert_not Azure.reads?(ApiReads::TOOL, "path" => "/subscriptions/#{SUBSCRIPTION}")
        %w[/subscriptions /tenants /providers/Microsoft.Management/managementGroups/root].each do |path|
          assert_raises(PolicyRefusal, path) { Azure.reading(ApiReads::TOOL, "path" => path, "query" => VERSION) }
        end
      end

      test "a key, a connection string and a SAS link are read as names, and a container's environment too" do
        shown = Azure.hidden(
          "properties" => { "InstrumentationKey" => "abc-123", "ConnectionString" => "InstrumentationKey=abc", "keySource" => "Microsoft.Storage",
                            "sendKeyName" => "RootManageSharedAccessKey", "sendKeyValue" => "s3cr3t", "logs" => { "url" => "https://x.blob.core.windows.net/l?sv=1&sig=abc" } }
        )

        assert_equal ApiReads::HIDDEN, shown.dig("properties", "InstrumentationKey")
        assert_equal ApiReads::HIDDEN, shown.dig("properties", "ConnectionString")
        assert_equal ApiReads::HIDDEN, shown.dig("properties", "sendKeyValue")
        assert_equal ApiReads::HIDDEN, shown.dig("properties", "logs", "url")
        assert_equal "Microsoft.Storage", shown.dig("properties", "keySource")
        assert_equal "RootManageSharedAccessKey", shown.dig("properties", "sendKeyName")
      end
    end
  end
end
