require "test_helper"

module Integrations
  module Packs
    class FactoryTest < ActiveSupport::TestCase
      ARGUMENTS = { "repo" => "acme/web", "title" => "Stop the checkout timeout", "brief" => "Checkout times out after the deploy." }.freeze
      COMPUTER = { "id" => "c1", "name" => "builder", "status" => "active",
                   "clonedRepoDirectories" => [ "/home/factory-user/projects/web", "/home/factory-user/projects/api" ] }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "factory", name: "Factory")
        @row = @integration.integration_environments.create!
        Factory.store_credentials!(@row, Factory::API_KEY => "fk_key")
        @row.store_fields!(Factory::COMPUTER => "builder")
        @reports = []
        @pack = Factory.new(@integration, progress: ->(text) { @reports << text })
        @pack.stubs(:pause)
        FactoryApi.any_instance.stubs(:computer_named).with("builder").returns(COMPUTER)
      end

      test "a change is a session in the repository's folder on the computer, sent the brief, and the pull request comes from the Droid's words" do
        FactoryApi.any_instance.expects(:create_session).with(
          "computerId" => "c1", "cwd" => "/home/factory-user/projects/web", "sessionSettings" => Factory::SESSION_SETTINGS
        ).returns("sessionId" => "s1", "status" => "idle")
        FactoryApi.any_instance.expects(:send_message).with { |id, text| id == "s1" && text.include?("Checkout times out after the deploy.") }
                  .returns("messageId" => "m1", "status" => "pending")
        FactoryApi.any_instance.stubs(:session).with("s1").returns("status" => "running", "factoryCredits" => 1.5)
                  .then.returns("status" => "idle", "factoryCredits" => 3.25)
        FactoryApi.any_instance.stubs(:messages).returns(
          "messages" => [ droid_said(2, "Opened https://github.com/acme/web/pull/4 with the fix."), droid_said(1, "Looking at the timeout.") ],
          "pagination" => { "hasMore" => false, "nextCursor" => nil }
        )

        text = @pack.fix_code(environment_row: @row, arguments: ARGUMENTS)["content"].first["text"]

        assert text.start_with?("Factory opened https://github.com/acme/web/pull/4 for acme/web.\nWhat Factory said: Opened https://github.com/acme/web/pull/4 with the fix.\nIt used 3.25 Factory credits.")
        assert_match %r{Open this in GitHub, and give the person this link with what you found: https://github.com/acme/web/pull/4\z}, text
        assert_equal "Factory is writing the change in session s1.", @reports.first
      end

      test "the region chosen on the connect form picks Factory's deployment, for the form's check and every call after" do
        FactoryApi.expects(:new).with("fk_key", "eu").returns(stub(computer_named: COMPUTER))
        assert_nil Factory.credential_refusal({ Factory::API_KEY => "fk_key" }, fields: { Factory::COMPUTER => "builder" },
                                              region: IntegrationProvider.find("factory").region("eu"))

        @integration.update!(settings: @integration.settings.to_h.merge(Integration::REGION_SETTING => "eu"))
        FactoryApi.expects(:new).with("fk_key", "eu").returns(stub(computer_named: COMPUTER))
        assert_nil @pack.check_health!(@row.reload)
      end

      test "a repository the computer has no copy of is refused before any session starts" do
        FactoryApi.any_instance.expects(:create_session).never

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS.merge("repo" => "acme/billing")) }

        assert_equal "The Droid Computer builder has no copy of acme/billing. Clone it there once, then hand the change over again.", error.message
      end

      test "the limit interrupts the Droid, and a refused session says what to ask Factory" do
        FactoryApi.any_instance.stubs(:create_session).returns("sessionId" => "s1")
        FactoryApi.any_instance.stubs(:send_message).returns("status" => "pending")
        FactoryApi.any_instance.stubs(:session).returns("status" => "running")
        FactoryApi.any_instance.expects(:interrupt).with("s1")
        @pack.stubs(:clock).returns(0, CodingAgent::TIME_LIMIT.to_i + 1)

        assert_match "Factory stopped without opening a pull request: Firefight stopped it at the 30 minute limit.",
                     assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }.message

        FactoryApi.any_instance.stubs(:create_session).raises(FactoryApi::Error.new("Factory answered 403: Not enabled", status: 403))
        assert_equal "Factory did not start the change. Factory answered 403: Not enabled. Factory switches its sessions API on for selected " \
                     "organizations, so ask Factory to switch it on for yours.",
                     assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }.message
      end

      test "a computer that is still being set up or failed is said on the form and by the health check" do
        FactoryApi.any_instance.stubs(:computer_named).returns(COMPUTER.merge("status" => "provisioning"))
        assert_equal "The Droid Computer builder is still being set up. Connect it once Factory shows it as active.",
                     Factory.credential_refusal({ Factory::API_KEY => "fk_key" }, fields: { Factory::COMPUTER => "builder" })

        FactoryApi.any_instance.stubs(:computer_named).returns(COMPUTER.merge("status" => "error"))
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }

        FactoryApi.any_instance.stubs(:computer_named).returns(COMPUTER)
        assert_nil Factory.credential_refusal({ Factory::API_KEY => "fk_key" }, fields: { Factory::COMPUTER => "builder" })
        assert_equal "Enter the Droid Computer's name.", Factory.credential_refusal({ Factory::API_KEY => "fk_key" }, fields: { Factory::COMPUTER => "" })
      end

      test "session_status has no session page to link, so it links the pull request when there is one" do
        FactoryApi.any_instance.stubs(:session).with("s1").returns("status" => "running")

        result = @pack.session_status(environment_row: @row, arguments: { "session" => "s1" })

        assert_equal "Factory session s1: working\nFactory gives no page for a session, so it is found in Factory's own app by its id.", result["content"].first["text"]
      end

      private

      def droid_said(at, text)
        { "id" => "m#{at}", "role" => "assistant", "createdAt" => at, "content" => [ { "type" => "text", "text" => text } ] }
      end
    end
  end
end
