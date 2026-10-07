require "test_helper"

module Integrations
  module ErrorReaders
    class CloudflareTest < ActiveSupport::TestCase
      test "Cloudflare saying the thing named is not there is a not found" do
        # What Cloudflare's server answered in the chat this was seen in.
        assert Cloudflare.not_found?("Error: Cloudflare API error: 8000007: Project not found. The specified project name does not match any of your existing projects.")
        assert Cloudflare.not_found?("Cloudflare API error: 10007: This Worker does not exist on your account.")
        assert Cloudflare.not_found?("Cloudflare API error: 7003: Could not route to /zones/nope/dns_records, perhaps your object identifier is invalid?")
        assert Cloudflare.not_found?("Cloudflare API error: 404 Not Found")
      end

      test "every other failure is an error, however it is worded" do
        [
          "Error: Cloudflare API error: 10000: Authentication error",
          "Cloudflare API error: 8000007: Project not found, 10000: Authentication error",
          "Cloudflare API error: 500 Internal Server Error",
          "Cloudflare API error: 403 Forbidden",
          "GraphQL error: unknown field zones",
          "Error: execution timed out",
          ""
        ].each { |said| assert_not Cloudflare.not_found?(said), said }
      end
    end
  end
end
