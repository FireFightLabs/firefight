ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

ActiveRecord::Encryption.configure(
  primary_key: "test_primary_key_12345678901234567890123456",
  deterministic_key: "test_deterministic_key_1234567890123456",
  key_derivation_salt: "test_salt_1234567890123456789012345678"
)

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

# Workflow classes register themselves on load.
Dir[Rails.root.join("app/workflows/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    # A per-class fixture list meant a forgotten parent table was a random FK violation under parallel execution.
    fixtures :all

    include SlackSignatureHelper
    include OmniauthTestHelper
    include SlackClientStubHelper
    include ApiTestHelper
    include InertiaTestHelper
    include EntitlementsTestHelper
    include SessionTestHelper
    include InviteGateTestHelper
  end
end
