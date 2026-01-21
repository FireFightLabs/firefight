ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

    # Don't load all fixtures by default - let each test specify what it needs
    # fixtures :all

    # Include test helpers
    include SlackSignatureHelper
    include OmniauthTestHelper
    include SlackClientStubHelper

    # Add more helper methods to be used by all tests here...
  end
end
