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
      FIX = Chat::Tools::Confirmation.new(
        tool_call_id: "call_2", question: "Fix code on GitHub, account FireFightLabs?", short_title: "Add a commit to PR #856",
        intent: "Address the review comments on PR #856 (commit 7bcec79c3, comment 2398811) as you asked",
        asked: [ %w[repo FireFightLabs/firefight], [ "brief", "Fix `invite_lead` per review 2398811" ] ], status: :awaiting,
        target: "GitHub, account FireFightLabs", call: "Fix code", tool_name: "github_fix_code"
      )
      DANA = Struct.new(:platform_user_id, :actor_display_name).new("U1", "Dana")

      def build(*confirmations, rich: true) = AgentConfirmation.build(conversation_id: "conv", confirmations: confirmations, rich: rich)

      def buttons(blocks) = blocks.flat_map { |block| block[:actions] || block[:elements] || [ block[:accessory] ].compact }.select { |element| element[:type] == "button" }

      test "a request is a card saying what Halon wants to do, one plain line, and Approve, Cancel and Details" do
        blocks = build(FIX)

        card = blocks.first
        assert_equal "card", card[:type]
        assert_equal ":raised_hand:  Halon wants to: add a commit to PR #856", card.dig(:title, :text)
        assert_equal "Address the review comments on PR #856 (commit, comment) as you asked.", card.dig(:body, :text)
        assert_equal [ [ "Approve", Identifiers::AGENT_CONFIRM, "primary" ], [ "Cancel", Identifiers::AGENT_CANCEL, nil ], [ "Details", Identifiers::AGENT_CONFIRMATION_DETAILS, nil ] ],
                     card[:actions].map { |button| [ button.dig(:text, :text), button[:action_id], button[:style] ] }
        assert_equal [ "conv:call_2" ], card[:actions].map { |button| button[:value] }.uniq
        assert_equal Identifiers::AGENT_ALLOW_FOR_CHAT, blocks.last.dig(:elements, 0, :action_id), "allowing it for the chat sits under the card"
        assert_equal "Halon wants to: add a commit to PR #856", AgentConfirmation.fallback([ FIX ])
      end

      test "the card leaves the tool, its arguments, ids, the reasons and the reads to Details" do
        text = build(FIX.with(read: Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Pr lookup 856", found: [ "856" ], from: "an answer from GitHub") ], others: 17))).to_json

        [ "github_fix_code", "FireFightLabs/firefight", "invite_lead", "7bcec79c3", "2398811", "Pr lookup", "17 more" ].each { |hidden| assert_not_includes text, hidden }
      end

      test "outside text holding the change's own values folds a caution into the line, and only then" do
        read = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Pr lookup 856", found: [ "856" ], from: "an answer from GitHub") ], others: 0)
        card = build(FIX.with(read: read)).first

        assert_includes card.dig(:body, :text), ":warning: _It read text from GitHub that other people wrote. Check this is what you want._"
        assert_operator card.dig(:body, :text).length, :<=, Slack::Blocks::Card::BODY_LIMIT

        generic = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [], from: "Northflank's docs") ], others: 21)
        assert_no_match(/:warning:/, build(FIX.with(read: generic)).to_json)
      end

      test "a change that cannot be undone or stops something says so in place of Halon's words" do
        card = build(FIX.with(effect: "Changes something in GitHub that cannot be undone.")).first

        assert_equal "Changes something in GitHub that cannot be undone.", card.dig(:body, :text)
      end

      test "the undo choice for a change customers feel stays on the message, starting on the one chosen so far" do
        undo = build(PAUSE).find { |block| block.dig(:accessory, :action_id) == Identifiers::AGENT_EXPIRY }

        assert_equal Integrations::Mitigations::STARTS_AGAIN, undo.dig(:text, :text)
        assert_equal [ "Never", "15 min", "1 h", "4 h", "24 h" ], undo.dig(:accessory, :options).map { |option| option.dig(:text, :text) }
        assert_equal "conv:call_1:60", undo.dig(:accessory, :initial_option, :value)
      end

      test "allowing it for the chat is not offered once something was read from outside" do
        read = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [], from: "Northflank's docs") ], others: 0)

        assert_not_includes buttons(build(FIX.with(read: read))).map { |button| button[:action_id] }, Identifiers::AGENT_ALLOW_FOR_CHAT
      end

      test "a workspace whose Slack refuses cards gets the same words as plain blocks" do
        blocks = build(FIX, rich: false)

        assert_equal "*:raised_hand:  Halon wants to: add a commit to PR #856*\nAddress the review comments on PR #856 (commit, comment) as you asked.", blocks.first.dig(:text, :text)
        assert_equal [ Identifiers::AGENT_CONFIRM, Identifiers::AGENT_CANCEL, Identifiers::AGENT_CONFIRMATION_DETAILS ], blocks.second[:elements].map { |button| button[:action_id] }
      end

      test "approved, it says who approved it and that it is working, and a code change shows its checklist" do
        working = build(FIX.with(status: :confirmed, decided_by: DANA)).sole
        assert_equal [ ":arrows_counterclockwise:  Add a commit to PR #856", "Approved by <@U1>  ·  working…" ], [ working.dig(:title, :text), working.dig(:body, :text) ]
        assert_equal [ Identifiers::AGENT_CONFIRMATION_DETAILS ], working[:actions].map { |button| button[:action_id] }

        work = Chat::CodeFixProgress.start(at: Time.utc(2026, 10, 16, 15, 5))
        work.changed!("app/workflows/lead_assignment_workflow.rb")
        blocks = build(FIX.with(status: :confirmed, decided_by: DANA, progress: work))
        assert_equal [ "plan", "Add a commit to PR #856" ], [ blocks.first[:type], blocks.first[:title] ]
        assert_equal [ "Write the change", "1 file changed" ], [ blocks.first.dig(:tasks, 0, :title), blocks.first.dig(:tasks, 0, :details, :elements, 0, :elements, 0, :text) ]
        assert_includes blocks.second.dig(:elements, 0, :text), "Approved by <@U1>  ·  started <!date^#{work.started_at.to_i}"
      end

      test "once it ran, one line says done with the page it made, failed with why, or cancelled by whom" do
        link = Chat::StepOutcome::Link.new(provider: "GitHub", url: "https://github.com/FireFightLabs/firefight/pull/856")
        answered = Chat::StepOutcome.new(kind: Chat::StepOutcome::KIND_ANSWERED, said: nil, lines: [], total: 0, size: 0, link: link)
        done = build(FIX.with(status: :confirmed, decided_by: DANA, outcome: answered)).sole
        assert_equal ":white_check_mark:  Add a commit to PR #856", done.dig(:title, :text)
        assert_equal "Done  ·  <https://github.com/FireFightLabs/firefight/pull/856|github.com/FireFightLabs/firefight/pull/856>  ·  approved by <@U1>", done.dig(:body, :text)

        failed_outcome = Chat::StepOutcome.new(kind: Chat::StepOutcome::KIND_FAILED, said: "The code sandbox did not start", lines: [], total: 0, size: 0, link: nil)
        failed = build(FIX.with(status: :confirmed, decided_by: DANA, outcome: failed_outcome)).sole
        assert_equal [ ":x:  Add a commit to PR #856", "Failed: The code sandbox did not start" ], [ failed.dig(:title, :text), failed.dig(:body, :text) ]

        cancelled = build(FIX.with(status: :cancelled, decided_by: DANA)).sole
        assert_equal [ ":no_entry_sign:  Add a commit to PR #856", "Cancelled by <@U1>" ], [ cancelled.dig(:title, :text), cancelled.dig(:body, :text) ]
        assert_equal "Add a commit to PR #856: cancelled.", AgentConfirmation.fallback([ FIX.with(status: :cancelled) ])

        waiting = build(FIX.with(status: :owner_asked, decided_by: DANA, waiting_on: "Bob Jones")).sole
        assert_equal "Approved by <@U1>  ·  waiting for Bob Jones to agree", waiting.dig(:body, :text)
        withdrawn = build(FIX.with(status: :withdrawn)).sole
        assert_equal AgentConfirmation::WITHDRAWN, withdrawn.dig(:body, :text)
      end

      test "the words came from the model, so they are escaped" do
        text = build(PAUSE.with(short_title: "Pause <!channel>", intent: "Ping <@U1>", target: "a & b")).to_json

        assert_no_match(/<!channel>|<@U1>/, text)
      end

      test "many questions at once keep every one's buttons under Slack's limit" do
        many = (1..20).map { |index| FIX.with(tool_call_id: "call_#{index}") }

        blocks = build(*many, rich: false)

        assert_operator blocks.size, :<=, AgentConfirmation::MAX_BLOCKS
        assert_equal 20, blocks.count { |block| block[:elements]&.any? { |element| element[:action_id] == Identifiers::AGENT_CONFIRM } }
      end
    end

    class AgentConfirmationDetailsTest < ActiveSupport::TestCase
      test "Details holds everything the card leaves out: where, Halon's words, the reasons, what was read and the call" do
        read = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [ "dev-web" ], from: "Northflank's docs") ], others: 21)
        view = Slack::Modals::AgentConfirmationDetails.build(AgentConfirmationTest::PAUSE.with(read: read, safeguards: [ [ "Rows it changes", "42 rows of orders" ] ]))

        text = view[:blocks].map { |block| block.dig(:text, :text) }.join("\n")
        [ "*Pause dev-web*", "Northflank, project firefight", "Pause the dev-web service so it stops running and stops billing, as you asked.",
          "Rows it changes: 42 rows of orders", "• dev-web memory pinned at 100% _(Query metrics dev-web)_",
          "Halon read Northflank's docs before asking.", "tool: northflank_api_request", "method: POST", "path: services/dev-web/pause",
          Chat::Tools::READ_HEADING, "• Read doc: Mentions dev-web", "• 21 more reads: Read earlier in this chat" ].each { |shown| assert_includes text, shown }
      end

      test "the warning about outside text is an alert block where the workspace shows the newer blocks" do
        read = Chat::Tools::Provenance::Read.new(sources: [ Chat::Tools::Provenance::Source.new(label: "Read doc", found: [ "dev-web" ], from: "Northflank's docs") ], others: 0)

        blocks = Slack::Modals::AgentConfirmationDetails.build(AgentConfirmationTest::PAUSE.with(read: read), rich: true)[:blocks]

        alert = blocks.find { |block| block[:type] == "alert" }
        assert_equal Slack::Blocks::Alert::LEVEL_WARNING, alert[:level]
      end

      test "a time in the call reads in each reader's own zone" do
        at = Time.zone.parse("2026-10-13 12:30 UTC")
        confirmation = AgentConfirmationTest::PAUSE.with(asked: [ [ "Runs", "Once at #{Chat::TimeToken.for(at)}" ] ], tool_name: nil)

        text = Slack::Modals::AgentConfirmationDetails.build(confirmation)[:blocks].map { |block| block.dig(:text, :text) }.join("\n")

        assert_includes text, "Runs: Once at <!date^#{at.to_i}^{date_long_pretty} at {time}|Tue 13 Oct 2026, 12:30 UTC>"
      end

      test "a browser send points at the page it sends from, posted above the request" do
        view = Slack::Modals::AgentConfirmationDetails.build(AgentConfirmationTest::PAUSE.with(page: Object.new, safeguards: [ [ "Sends", "POST https://shop.example.com/orders" ] ]))

        text = view.to_json
        assert_includes text, Slack::Modals::AgentConfirmationDetails::PAGE_ABOVE
        assert_includes text, "POST https://shop.example.com/orders"
      end
    end
  end
end
