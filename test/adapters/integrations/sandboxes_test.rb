require "test_helper"

module Integrations
  class SandboxesTest < ActiveSupport::TestCase
    setup do
      ENV.stubs(:[]).with(anything).returns(nil)
    end

    test "a released install starts boxes from the sandbox image released with it" do
      ENV.stubs(:[]).with("FIREFIGHT_RELEASE").returns("0.0.8")

      assert_equal "ghcr.io/firefightlabs/firefight-sandbox:0.0.8", Sandboxes.image
    end

    test "an install that is not a release starts boxes from the edge build" do
      assert_equal "ghcr.io/firefightlabs/firefight-sandbox:edge", Sandboxes.image
    end

    test "an image named in SANDBOX_IMAGE wins over the default" do
      ENV.stubs(:[]).with("FIREFIGHT_RELEASE").returns("0.0.8")
      ENV.stubs(:[]).with("SANDBOX_IMAGE").returns("firefight-sandbox:dev")

      assert_equal "firefight-sandbox:dev", Sandboxes.image
    end
  end
end
