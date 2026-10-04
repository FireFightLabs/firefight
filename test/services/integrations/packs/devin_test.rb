require "test_helper"

module Integrations
  module Packs
    class DevinTest < ActiveSupport::TestCase
      ARGUMENTS = { "repo" => "acme/web", "title" => "Stop the checkout timeout", "brief" => "Checkout times out after the deploy.",
                    "summary" => "Raise the timeout to what the gateway allows" }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin")
        @row = @integration.integration_environments.create!
        Devin.store_credentials!(@row, Devin::API_KEY => " cog_key ")
        @row.store_fields!(Devin::ORGANIZATION => "org-abc")
        @reports = []
        @pack = Devin.new(@integration, progress: ->(text) { @reports << text })
        @pack.stubs(:pause)
      end

      test "the provider's details say what Firefight does with it in its own words" do
        assert_equal "Firefight hands a fix's code change to Devin once you choose it under Settings, Workspace and switch on fix_code. " \
                     "Halon follows the change with session_status. An investigation never starts one.",
                     Capabilities.halon_sentence("devin", "Devin")
      end

      test "fix_code changes code and arrives switched off, session_status only reads" do
        definitions = Devin.tool_definitions.index_by(&:name)

        assert_not definitions["fix_code"].read_only
        assert definitions["session_status"].read_only
        assert_equal "cog_key", @row.reload.credentials_hash[Devin::API_KEY]
      end

      test "a change is a session with the brief and the ACU limit, followed until Devin opens the pull request" do
        DevinApi.any_instance.expects(:create_session).with do |body|
          body["title"] == "Stop the checkout timeout" && body["max_acu_limit"] == 5 &&
            body["prompt"].start_with?("Fix this in the repository acme/web.") && body["prompt"].include?("Checkout times out after the deploy.") &&
            body["prompt"].include?("Its description says what it does and why: Raise the timeout to what the gateway allows.")
        end.returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
        DevinApi.any_instance.stubs(:session).returns(session("running", "working"))
                .then.returns(session("running", "waiting_for_user", prs: [ "https://github.com/acme/web/pull/7" ], acus: 2.345))
        DevinApi.any_instance.stubs(:messages).returns("items" => [ { "source" => "devin", "message" => "Raised the timeout and added a test." } ])

        text = result_text(@pack.fix_code(environment_row: @row, arguments: ARGUMENTS))

        assert text.start_with?("Devin opened https://github.com/acme/web/pull/7 for acme/web.\nWhat Devin said: Raised the timeout and added a test.\nIt used 2.35 ACUs.")
        assert_match "Follow it at https://app.devin.ai/sessions/devin-1.", text
        assert_match %r{Open this in GitHub, and give the person this link with what you found: https://github.com/acme/web/pull/7\z}, text
        assert_equal "Devin is writing the change in session devin-1. Follow it at https://app.devin.ai/sessions/devin-1.", @reports.first
      end

      test "the ACU limit the connection sets is Devin's, and anything that looks like a credential never reaches Devin" do
        @row.store_fields!(Devin::ORGANIZATION => "org-abc", Devin::MAX_ACUS => "12")
        DevinApi.any_instance.expects(:create_session).with do |body|
          body["max_acu_limit"] == 12 && body["prompt"].include?("[REDACTED:github_token]") && !body["prompt"].include?("ghp_")
        end.returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
        DevinApi.any_instance.stubs(:session).returns(session("exit", nil, prs: [ "https://github.com/acme/web/pull/8" ]))
        DevinApi.any_instance.stubs(:messages).returns("items" => [])

        @pack.fix_code(environment_row: @row.reload, arguments: ARGUMENTS.merge("brief" => "The log had ghp_#{'a' * 36} in it."))
      end

      test "a question while working is reported as waiting for a person, and the limit stops the session" do
        DevinApi.any_instance.stubs(:create_session).returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
        DevinApi.any_instance.stubs(:session).returns(session("running", "waiting_for_user"))
        DevinApi.any_instance.expects(:terminate).with("devin-1")
        @pack.stubs(:clock).returns(0, CodingAgent::TIME_LIMIT.to_i + 1)

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }

        assert error.message.start_with?("Devin stopped without opening a pull request: Firefight stopped it at the 30 minute limit.")
        assert_includes @reports.last, "Devin is waiting for a person: it asked a question in its session. Follow it at https://app.devin.ai/sessions/devin-1."
      end

      test "a session Devin suspends, or one that ends without a pull request, fails with why and where to look" do
        DevinApi.any_instance.stubs(:create_session).returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
        DevinApi.any_instance.stubs(:messages).returns("items" => [ { "source" => "devin", "message" => "I could not reproduce it." } ])
        DevinApi.any_instance.stubs(:session).returns(session("suspended", "usage_limit_exceeded", acus: 5))

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }
        assert_equal "Devin stopped without opening a pull request: it reached its usage limit.\nWhat Devin said: I could not reproduce it.\n" \
                     "It used 5.0 ACUs.\nFollow it at https://app.devin.ai/sessions/devin-1.", error.message

        DevinApi.any_instance.stubs(:session).returns(session("exit", nil))
        assert_match "Devin finished without opening a pull request.", assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }.message
      end

      test "a few failed reads are waited out, and more say Firefight lost the session with its link" do
        DevinApi.any_instance.stubs(:create_session).returns("session_id" => "devin-1", "url" => "https://app.devin.ai/sessions/devin-1")
        DevinApi.any_instance.stubs(:session).raises(DevinApi::Error.new("Devin answered 502: Bad gateway"))

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }

        assert_equal "Firefight could not read Devin's session devin-1. Devin answered 502: Bad gateway. Follow it at https://app.devin.ai/sessions/devin-1.", error.message
      end

      test "a refused start says what to change" do
        DevinApi.any_instance.stubs(:create_session).raises(DevinApi::Forbidden.new("Devin answered 403: Forbidden"))

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }

        assert_equal "Devin did not start the change. Devin answered 403: Forbidden. The service user needs the UseDevinSessions permission " \
                     "to start sessions and ManageOrgSessions to stop one.", error.message
      end

      test "session_status says where a session stands and links to its pull request, or to the session" do
        DevinApi.any_instance.stubs(:session).returns(session("running", "working").merge("url" => "https://app.devin.ai/sessions/devin-1"))

        text = result_text(@pack.session_status(environment_row: @row, arguments: { "session" => "devin-1" }))

        assert text.start_with?("Devin session devin-1: working")
        assert_match %r{Open this in Devin, and give the person this link with what you found: https://app.devin.ai/sessions/devin-1\z}, text
      end

      test "the organization and the ACU limit are connect fields the registry checks, never stored as credentials" do
        fields = IntegrationProvider.find("devin").connect_fields.index_by(&:key)

        assert_equal [ Devin::API_KEY ], Devin.credential_fields.map(&:key)
        assert_nil fields.fetch(Devin::ORGANIZATION).refusal("org-abc123")
        assert_match "org- followed by letters, numbers, dashes and underscores", fields.fetch(Devin::ORGANIZATION).refusal("abc").to_s
        assert fields.fetch(Devin::MAX_ACUS).optional
        assert_equal 5, ConnectionSettings.of(@row).field(Devin::MAX_ACUS).to_i, "a limit left empty is Devin's default from the registry"
        assert_nil @row.reload.credentials_hash[Devin::ORGANIZATION]
      end

      test "the key is checked against Devin, and a service user of another organization is refused on the form" do
        assert_equal "Enter the ACU limit as a whole number above zero, or leave it empty.",
                     Devin.credential_refusal({ Devin::API_KEY => "cog_key" }, fields: { Devin::ORGANIZATION => "org-abc", Devin::MAX_ACUS => "0" })
        DevinApi.any_instance.stubs(:whoami).returns("principal_type" => "service_user", "org_id" => "org-other")
        assert_equal "This service user belongs to the organization org-other, not org-abc.",
                     Devin.credential_refusal({ Devin::API_KEY => "cog_key" }, fields: { Devin::ORGANIZATION => "org-abc" })
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }

        DevinApi.any_instance.stubs(:whoami).returns("principal_type" => "pat_user", "org_id" => "org-other")
        assert_nil Devin.credential_refusal({ Devin::API_KEY => "cog_key" }, fields: { Devin::ORGANIZATION => "org-abc" })
        assert_nil @pack.check_health!(@row)

        DevinApi.any_instance.stubs(:whoami).raises(DevinApi::Unauthorized.new("Devin answered 401: Unauthorized"))
        assert_equal "Devin refused this key. Devin answered 401: Unauthorized", Devin.credential_refusal({ Devin::API_KEY => "cog_key" }, fields: { Devin::ORGANIZATION => "org-abc" })
      end

      private

      def session(status, detail, prs: [], acus: 1)
        { "session_id" => "devin-1", "status" => status, "status_detail" => detail, "acus_consumed" => acus,
          "pull_requests" => prs.map { |url| { "pr_url" => url, "pr_state" => "open" } } }
      end

      def result_text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
