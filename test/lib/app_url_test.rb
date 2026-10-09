require "test_helper"

class AppUrlTest < ActiveSupport::TestCase
  test "a link is on Firefight's own address when it is set, and the path alone when it is not" do
    set = { "APP_HOST" => "ff.example", "APP_PROTOCOL" => "http" }

    assert_equal({ host: "ff.example", protocol: "http" }, AppUrl.options(set))
    assert_equal "http://ff.example/app/map", AppUrl.absolute("/app/map", set)
    assert_equal "https://ff.example", AppUrl.root({ "APP_HOST" => "ff.example" })
    assert_nil AppUrl.options({})
    assert_equal "/app/map", AppUrl.absolute("/app/map", {})
  end
end
