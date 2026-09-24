require "test_helper"

class CodeChange::OwnersTest < ActiveSupport::TestCase
  setup do
    @owners = CodeChange::Owners.new(<<~TEXT)
      # Everyone owns what nobody else claims
      * @acme/everyone
      /app/models/ @acme/data
      docs/ @acme/writers
      *.tf @acme/infra
    TEXT
  end

  test "the last matching line wins, as on the code hosts" do
    assert_equal [ "@acme/data" ], @owners.for("app/models/pool.rb")
    assert_equal [ "@acme/infra" ], @owners.for("infra/main.tf")
    assert_equal [ "@acme/everyone" ], @owners.for("app/controllers/checkout_controller.rb")
  end

  test "a folder without a leading slash matches at any depth, one with it only at the root" do
    assert_equal [ "@acme/writers" ], @owners.for("guides/docs/setup.md")
    assert_equal [ "@acme/everyone" ], @owners.for("lib/app/models/pool.rb")
  end
end
