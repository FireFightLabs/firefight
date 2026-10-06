require "test_helper"

module Slack
  module Messages
    class AgentConfirmationTest < ActiveSupport::TestCase
      test "a call through a connection leads with what it reaches, then the call, with the agent's words after" do
        confirmation = Chat::Tools::Confirmation.new(
          tool_call_id: "call_1", question: "Api request on Faylee (Northflank), project faylee?", intent: "Scale Faylee's web to 0",
          asked: [ %w[path services/web/scale] ], status: :awaiting, target: "Faylee (Northflank), project faylee", call: "Api request"
        )

        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: [ confirmation ])

        assert_equal "*Faylee (Northflank), project faylee*\nApi request", blocks[1][:text][:text]
        assert_equal "Scale Faylee's web to 0  ·  path: services/web/scale", blocks[2][:elements].sole[:text]
        assert_equal "Waiting for you to confirm: Api request on Faylee (Northflank), project faylee?", AgentConfirmation.fallback([ confirmation ])
      end

      test "a call with no target leads with the agent's words as before" do
        confirmation = Chat::Tools::Confirmation.new(
          tool_call_id: "call_1", question: "Delete permission set?", intent: "Remove the unused set", asked: [ %w[slug set_1] ],
          status: :awaiting, target: nil, call: nil
        )

        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: [ confirmation ])

        assert_equal "*Remove the unused set*", blocks[1][:text][:text]
        assert_equal "Delete permission set  ·  slug: set_1", blocks[2][:elements].sole[:text]
      end
    end
  end
end
