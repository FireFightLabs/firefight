ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Workflow tests create minimal data directly - no fixtures needed
    # fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
