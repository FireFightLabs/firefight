require "test_helper"

class UserAgentTest < ActiveSupport::TestCase
  test "a request that names no program or only Ruby's default is named Firefight, and one with its own name keeps it" do
    plain = Net::HTTP::Get.new(URI("https://example.com/"))
    assert_equal "Ruby", plain["User-Agent"]
    assert_equal "Firefight/1.0 (+https://firefight.app)", UserAgent.apply!(plain)["User-Agent"]

    own = Net::HTTP::Get.new(URI("https://example.com/"), "User-Agent" => "FirefightDocs/1.0")
    assert_equal "FirefightDocs/1.0", UserAgent.apply!(own)["User-Agent"]
  end
end
