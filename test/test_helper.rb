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

# Built once here, before the parallel workers fork. Otherwise each worker that renders a page builds on its own, and
# one empties the output while another reads the manifest or its browser loads from it.
ViteRuby.commands.build || raise("The Vite build failed, see log/test.log")

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
    include LlmResponseHelper
    include MapReaderHelper
    include TwoEnvironmentMapHelper
    include SettingValuesHelper
    include HalonAccessHelper
    include AiAccountTestHelper
    include ProviderDocsHelper

    # The investigator is given each connection's read pack when the connection is made. A test of what it reaches without
    # a grant takes them back first.
    def revoke_investigator_packs!(workspace)
      workspace.ability_grants.where(principal: SystemAgent.investigator).where.not(role_id: nil).destroy_all
    end
  end
end
