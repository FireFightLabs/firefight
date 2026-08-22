require "test_helper"

class AllowedHostsTest < ActiveSupport::TestCase
  test "parses a comma separated list and trims each entry" do
    assert_equal [ "app.firefight.test", "firefight.test" ],
                 AllowedHosts.parse!(" app.firefight.test , firefight.test ")
  end

  test "keeps a single host" do
    assert_equal [ "app.firefight.test" ], AllowedHosts.parse!("app.firefight.test")
  end

  # Rails skips host authorization entirely when the list is empty, so every
  # way of arriving at "nothing" has to stop the boot instead.
  test "refuses a value that names no host" do
    [ "", "   ", ",", " , , " ].each do |raw|
      assert_raises(AllowedHosts::MissingError, "#{raw.inspect} should not pass") do
        AllowedHosts.parse!(raw)
      end
    end
  end

  test "drops blank entries rather than passing them to Rails" do
    assert_equal [ "a.test", "b.test" ], AllowedHosts.parse!("a.test,,b.test,")
  end

  test "names the variable it was reading" do
    error = assert_raises(AllowedHosts::MissingError) { AllowedHosts.parse!("", source: "APP_HOST") }

    assert_match "APP_HOST", error.message
  end
end
