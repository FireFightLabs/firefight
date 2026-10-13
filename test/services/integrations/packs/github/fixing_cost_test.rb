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
      end
    end
  end
end
