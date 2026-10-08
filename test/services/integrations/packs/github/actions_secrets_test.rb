require "test_helper"
require "rbnacl"

module Integrations
  module Packs
    class Github
      class ActionsSecretsTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
          @private_key = RbNaCl::PrivateKey.generate
          @key = { "key_id" => "568250167242549743", "key" => Base64.strict_encode64(@private_key.public_key.to_bytes) }
        end

        test "a repository's secrets are listed by name and date, never value" do
          GithubApp.expects(:get).with("/repos/acme/web/actions/secrets?per_page=100", token: "ghs_token")
                   .returns("total_count" => 1, "secrets" => [ { "name" => "DEPLOY_HOOK", "created_at" => "2026-09-01T10:00:00Z", "updated_at" => "2026-10-01T10:00:00Z" } ])

          text = text_of(@pack.list_actions_secrets(environment_row: @row, arguments: { "repo" => "acme/web" }))

          assert_includes text, "Actions secrets in acme/web:\n  DEPLOY_HOOK  last set 2026-10-01T10:00:00Z"
          assert text.end_with?("https://github.com/acme/web/settings/secrets/actions")
        end

        test "an environment's secrets need the Environments permission, said when GitHub refuses" do
          GithubApp.stubs(:get).with("/repos/acme/web/environments/production/secrets?per_page=100", token: "ghs_token")
                   .raises(GithubApp::NotPermitted, "Resource not accessible by integration")

          error = assert_raises(NativePack::Error) { @pack.list_actions_secrets(environment_row: @row, arguments: { "repo" => "acme/web", "environment" => "production" }) }

          assert_includes error.message, "Firefight's GitHub App needs Environments read on this installation for an environment's secrets"
        end

        test "setting a secret never takes its value, checks the key first and answers with where it goes" do
          GithubApp.expects(:get).with("/repos/acme/web/actions/secrets/public-key", token: "ghs_token").returns(@key)
          GithubApp.expects(:write).never

          result = @pack.set_actions_secret(environment_row: @row, arguments: { "repo" => "acme/web", "name" => "deploy_hook_url" })

          entry = SecretHandoffs.entry_of(result)
          assert_equal({ "repo" => "acme/web", "name" => "DEPLOY_HOOK_URL" }, entry["target"])
          assert_equal "DEPLOY_HOOK_URL in acme/web", entry["title"]
          assert_includes text_of(result), SecretHandoffs::NOT_IN_A_CHAT
          refute Github.tool_definitions.find { |tool| tool.name == "set_actions_secret" }.params_schema["properties"].key?("value")
        end

        test "a name GitHub would refuse is refused before anything is asked" do
          [ "GITHUB_TOKEN", "1ST", "has-dash" ].each do |name|
            assert_raises(NativePack::Error) { @pack.set_actions_secret(environment_row: @row, arguments: { "repo" => "acme/web", "name" => name }) }
          end
        end

        test "a value is sealed with the repository's key and sent, never in the clear" do
          GithubApp.expects(:get).with("/repos/acme/web/environments/production/secrets/public-key", token: "ghs_token").returns(@key)
          sent = nil
          GithubApp.expects(:write).with do |verb, path, body, token:|
            sent = body
            verb == :put && path == "/repos/acme/web/environments/production/secrets/DEPLOY_HOOK" && token == "ghs_token"
          end.returns({})

          said = @pack.fill_secret(environment_row: @row, target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK", "environment" => "production" }, value: "s3cret")

          assert_equal "Set DEPLOY_HOOK in the production environment of acme/web.", said
          assert_equal @key["key_id"], sent["key_id"]
          refute_includes sent.to_json, "s3cret"
          assert_equal "s3cret", RbNaCl::Boxes::Sealed.from_private_key(@private_key).open(Base64.strict_decode64(sent["encrypted_value"]))
        end

        test "the tools need the Secrets permission" do
          assert_includes Github.needs_sentence("list_actions_secrets"), "needs Secrets read on this installation"
          assert_includes Github.needs_sentence("set_actions_secret"), "Secrets read and write"
        end

        private

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
