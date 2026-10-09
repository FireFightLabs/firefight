require "test_helper"

# Asks the configured model the question that went wrong in a real change. It calls the model, so it runs only when asked
# for (LIVE_MODELS=1) with a key configured, never in CI on its own.
class FirefightAi::QuestionAnswererLiveTest < ActiveSupport::TestCase
  # The person's words cover creating a workspace silently. The question is whether to create one when the person
  # chooses to, which the words do not address, so the person has to be asked.
  KNOWN = <<~KNOWN.freeze
    What the person asked, in their own words:
    > When someone signs in with Slack and their Slack team has no workspace yet, offer to connect it to a workspace they
    > already have that is not connected to Slack. Never silently create another workspace.
  KNOWN
  QUESTION = "Maya runs the Acme workspace, which is not connected to Slack. She signs in with Slack from the Acme Slack " \
             "team, which no workspace uses yet. Today Firefight creates a new workspace for that team without asking. " \
             "With the change, what should the signup page offer her?".freeze
  OPTIONS = [
    [ "Only pick an existing one", "Maya can only connect Acme, and signup never makes a new workspace while unconnected ones exist" ],
    [ "Pick one or create one", "Maya chooses between connecting Acme and a new workspace, which is made only when she chooses it" ]
  ].freeze

  setup do
    skip "Set LIVE_MODELS=1 with a model key to ask the model" unless ENV["LIVE_MODELS"] == "1" && model_key?
  end

  test "a case the person's words do not cover goes to the person, even with a recommendation that claims it does" do
    reply = FirefightAi::QuestionAnswerer.new(workspaces(:slack_workspace_one)).answer(
      question: QUESTION, known: KNOWN, options: OPTIONS,
      recommended: "Only pick an existing one, you asked that signup never create another workspace while unconnected ones exist"
    )

    assert_nil reply, "Halon answered #{reply&.text.inspect} for a case the person's words leave open"
  end

  private

  def model_key?
    config = RubyLLM.config
    [ config.anthropic_api_key, config.openai_api_key, config.openrouter_api_key ].any?(&:present?)
  end
end
