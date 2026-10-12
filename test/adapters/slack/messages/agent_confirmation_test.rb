require "test_helper"

module Slack
  module Messages
    class AgentConfirmationTest < ActiveSupport::TestCase
      PAUSE = Chat::Tools::Confirmation.new(
        tool_call_id: "call_1", question: "Api request on Northflank, project firefight?", short_title: "Pause dev-web",
        intent: "Pause the dev-web service so it stops running and stops billing, as you asked",
        asked: [ %w[method POST], %w[path services/dev-web/pause] ], status: :awaiting, target: "Northflank, project firefight", call: "Api request",
        tool_name: "northflank_api_request", support: [ Chat::Tools::LookFirst::Support.new(label: "Query metrics dev-web", said: "dev-web memory pinned at 100%") ],
        expires: Chat::Tools.expiries(Chat::Mitigation.new(status: Chat::Mitigation::STATUS_PROPOSED)), chosen_expiry: "60",
        undo_words: Integrations::Mitigations::STARTS_AGAIN
      )

      def texts(blocks) = blocks.map { |block| block.dig(:text, :text) || block[:elements]&.map { |element| element[:text].is_a?(Hash) ? element.dig(:text, :text) : element[:text] }&.join(" ") }

      test "a change leads with what will happen and where, then what it does and why, the undo choice, the buttons, and the call last" do
        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE ])

        assert_equal "divider", blocks[1][:type]
        assert_equal [
          AgentConfirmation::TITLE,
          nil,
          "*Pause dev-web*",
          "Northflank, project firefight",
          "Pause the dev-web service so it stops running and stops billing, as you asked.",
          "*Why*\n• dev-web memory pinned at 100% _(Query metrics dev-web)_",
          "Start it again automatically",
          "Pause dev-web Allow for this chat Cancel",
          "tool: northflank_api_request  ·  method: POST  ·  path: services/dev-web/pause"
        ], texts(blocks)
        assert_equal "context", blocks[3][:type], "where it happens is quiet"
        assert_equal "section", blocks[5][:type], "why is normal text"
        assert_equal "context", blocks.last[:type], "the call itself is quiet, at the foot"
        assert_equal "Waiting for you to confirm: Pause dev-web", AgentConfirmation.fallback([ PAUSE ])
      end

      test "the undo choice offers its times in order from never and starts on the one chosen so far" do
        undo = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE ]).find { |block| block.dig(:accessory, :action_id) == Identifiers::AGENT_EXPIRY }

        assert_equal [ "Never", "15 min", "1 h", "4 h", "24 h" ], undo.dig(:accessory, :options).map { |option| option.dig(:text, :text) }
        assert_equal "conv:call_1:60", undo.dig(:accessory, :initial_option, :value)
        kept = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE.with(chosen_expiry: Chat::Mitigation::KEEP) ])
        assert_equal "Never", kept.find { |block| block[:accessory] }.dig(:accessory, :initial_option, :text, :text)
      end

      test "the buttons name the change, offer allowing it for the chat only where it may be, and an answer replaces them" do
        allowed = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE ]).find { |block| block[:type] == "actions" }[:elements]
        assert_equal [ Identifiers::AGENT_CONFIRM, Identifiers::AGENT_ALLOW_FOR_CHAT, Identifiers::AGENT_CANCEL ], allowed.map { |element| element[:action_id] }
        assert_equal "primary", allowed.first[:style]

        read = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [], from: "Northflank's docs") ], others: 0)
        guarded = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE.with(read: read) ])
        assert_equal [ Identifiers::AGENT_CONFIRM, Identifiers::AGENT_CANCEL ], guarded.find { |block| block[:type] == "actions" }[:elements].map { |element| element[:action_id] }

        done = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE.with(status: :confirmed) ])
        assert_nil done.find { |block| block[:type] == "actions" || block[:accessory] }
        assert_includes texts(done), ":white_check_mark: Confirmed"
      end

      test "outside text with no value of this change's own is listed with the call, and warns only once it holds one" do
        generic = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [], from: "Northflank's docs") ], others: 21)
        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE.with(read: generic) ])

        assert_no_match(/:warning:/, blocks.to_json)
        assert_includes texts(blocks).last, Chat::Tools::READ_HEADING
        assert_includes texts(blocks).last, "• Read doc: Read earlier in this chat\n• 21 more reads: Read earlier in this chat"

        specific = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [ "dev-web" ], from: "Northflank's docs") ],
                                                     others: 0)
        warned = AgentConfirmation.build(conversation_id: "conv", confirmations: [ PAUSE.with(read: specific) ])
        warning = warned.index { |block| block.to_json.include?(":warning:") }
        assert_equal ":warning: Halon read Northflank's docs before asking. Check the reason above is yours.", texts(warned)[warning]
        assert warning < warned.index { |block| block[:type] == "actions" }, "the warning comes before the buttons"
        assert_includes texts(warned).last, "• Read doc: Mentions dev-web"
      end

      test "a call asked before short titles reads as it did, under the agent's sentence, with Confirm" do
        confirmation = Chat::Tools::Confirmation.new(
          tool_call_id: "call_1", question: "Delete permission set?", intent: "Remove the unused set", asked: [ %w[slug set_1] ],
          status: :awaiting, target: nil, call: nil
        )

        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: [ confirmation ])

        assert_equal [ AgentConfirmation::TITLE, nil, "*Remove the unused set*", "Delete permission set", "Confirm Allow for this chat Cancel", "slug: set_1" ], texts(blocks)
      end

      test "the words came from the model, so they are escaped" do
        confirmation = PAUSE.with(short_title: "Pause <!channel>", intent: "Ping <@U1>", target: "a & b")

        text = AgentConfirmation.build(conversation_id: "conv", confirmations: [ confirmation ]).to_json

        assert_no_match(/<!channel>|<@U1>/, text)
      end

      test "many questions at once fold each one down so the message stays under Slack's limit" do
        many = (1..7).map { |index| PAUSE.with(tool_call_id: "call_#{index}") }

        blocks = AgentConfirmation.build(conversation_id: "conv", confirmations: many)

        assert_operator blocks.size, :<=, AgentConfirmation::MAX_BLOCKS
        assert_equal 7, blocks.count { |block| block[:type] == "actions" }
        assert_includes texts(blocks), "*Pause dev-web*\nPause the dev-web service so it stops running and stops billing, as you asked."
      end
    end
  end
end
