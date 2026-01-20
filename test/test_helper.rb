ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

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

    # Include Slack signature helper
    include SlackSignatureHelper

    # Add more helper methods to be used by all tests here...
  end
end
