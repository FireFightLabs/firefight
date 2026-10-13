require "test_helper"

module Integrations
  module Packs
    class Github
      # What a code fix costs: the client its agent speaks to the model with, and the line each change logs with what it
      # spent and how it ended.
      class FixingCostTest < ActiveSupport::TestCase
        setup do
          @workspace = workspaces(:slack_workspace_one)
          integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @pack = Github.new(integration, box_key: "investigation-1")
          AppUrl.stubs(:root).returns("https://ff.example.com")
        end

        test "a model reached in Anthropic's own format is spoken to with OpenCode's Anthropic client, on OpenRouter too" do
          { [ "openrouter", "anthropic/claude-sonnet-5.5" ] => Fixing::ANTHROPIC_CLIENT, [ "anthropic", "claude-sonnet-5-5" ] => Fixing::ANTHROPIC_CLIENT,
            [ "openrouter", "z-ai/glm-5.3" ] => nil, [ "openai", "gpt-5.6" ] => nil }.each do |(provider, model), client|
            config = @pack.send(:agent_config, FirefightAi::ModelChoice.new(model: model, provider: provider), "token")

            assert_equal [ client ], [ config.dig("provider", provider, "npm") ], "#{provider} #{model}"
            assert_equal "https://ff.example.com/code_agent/#{provider}", config.dig("provider", provider, "options", "baseURL")
            assert_equal({}, config.dig("provider", provider, "models", model))
          end
        end

        test "each change logs what its writing and reviews spent and how it ended, so the cost of a fix that lands can be read" do
          session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-5-5", provider: "anthropic"),
                                            repository: "acme/api")
          [ [ CodeAgentSession::FEATURE, 3_000 ], [ CodeAgentSession::FEATURE, 4_000 ], [ FirefightAi::ChangeReviewer::FEATURE, 9_000 ] ].each do |feature, cost|
            Inference.create!(workspace: @workspace, feature: feature, provider: "anthropic", model: "claude-sonnet-5-5", inferable: session, input_tokens: 100,
                              output_tokens: 10, cost_micros: cost, status: Inference::STATUS_SUCCESS, paid_by: Inference::PAID_BY_OPERATOR)
          end
          logged = []
          Rails.logger.stubs(:info).with { |line| logged << JSON.parse(line) if line.include?("code_fix.spent") }

          @pack.send(:spent, session, nil)
          @pack.send(:spent, session, Fixing::Paused.new("paused"))
          @pack.send(:spent, session, Integrations::Error.new("refused"))

          assert_equal %w[pushed paused failed], logged.map { |line| line["outcome"] }
          assert_equal [ nil, "Integrations::Packs::Github::Fixing::Paused", "Integrations::Error" ], logged.map { |line| line["stopped_by"] }
          spend = logged.first["spend"]
          assert_equal [ 2, 7_000 ], spend[CodeAgentSession::FEATURE].values_at("calls", "cost_micros")
          assert_equal [ 1, 9_000 ], spend[FirefightAi::ChangeReviewer::FEATURE].values_at("calls", "cost_micros")
          assert_equal [ session.id, "claude-sonnet-5-5" ], logged.first.values_at("session", "model")
        end

        test "a spend log that cannot be written never replaces the change's own error or stops the session closing" do
          integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub 2")
          row = integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          pack = Github.new(integration, box_key: "investigation-1")
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:get).with("/repos/acme/api", token: "ghs_token").returns("default_branch" => "main")
          GithubApp.stubs(:get).with("/repos/acme/api/branches/main", token: "ghs_token").returns("commit" => { "sha" => "n" * 40 })
          FirefightAi.stubs(:choices_for).returns([ FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic") ])
          FirefightAi.stubs(:priced_for?).returns(true)
          CodeReading.any_instance.stubs(:prepare).returns({})
          CiSetup.stubs(:for).returns(nil)
          CiSetup.stubs(:absent).returns(nil)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN }
                     .returns("stdout" => "AGENT_EXIT 0\nBASE start-sha\nNOTHING\nLOG\n", "timed_out" => false)
          CodeAgentSession.any_instance.stubs(:spend).raises(ActiveRecord::StatementInvalid, "the ledger is gone")
          warned = []
          Rails.logger.stubs(:warn).with { |line| warned << line }

          error = assert_raises(Integrations::Error) do
            pack.fix_code(environment_row: row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_match "The coding agent changed nothing in acme/api.", error.message
          assert_not_nil CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api").closed_at, "the session still closes"
          assert(warned.any? { |line| line.include?("code_fix.spent_failed") && line.include?("ActiveRecord::StatementInvalid") })
        end
      end
    end
  end
end
