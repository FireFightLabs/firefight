ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

# Configure encryption for test environment
ActiveRecord::Encryption.configure(
  primary_key: "test_primary_key_12345678901234567890123456",
  deterministic_key: "test_deterministic_key_1234567890123456",
  key_derivation_salt: "test_salt_1234567890123456789012345678"
)

# Load test support files
Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

# Eager load workflow classes so they register themselves
Dir[Rails.root.join("app/workflows/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Every fixture, always. A per-class list meant a forgotten parent table
    # was a random FK violation under parallel execution; one constant set
    # loads once per worker and the failure mode is gone.
    fixtures :all

    # Include test helpers
    include SlackSignatureHelper
    include OmniauthTestHelper
    include SlackClientStubHelper
    include ApiTestHelper
    include InertiaTestHelper
    include EntitlementsTestHelper
    include SessionTestHelper

    # Add more helper methods to be used by all tests here...
  end
end
