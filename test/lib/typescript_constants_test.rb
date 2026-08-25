require "test_helper"

class TypescriptConstantsTest < ActiveSupport::TestCase
  test "the generated constants module is current" do
    assert TypescriptConstants.current?,
           "app/frontend/lib/generated/constants.ts has drifted from the Ruby constants, run bin/rails typescript:constants"
  end
end
