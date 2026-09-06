module Slack
  module Messages
    # Coaching messages for the first test incident, one step per message.
    module FirstIncidentWalkthrough
      COMMANDS_DOCS_URL = "https://firefight.app/docs/incidents/slack-commands/".freeze
      MCP_DOCS_URL = "https://firefight.app/docs/api/mcp-server/".freeze

      SCRIPT = [
        "Customers are seeing 502s on checkout since 14:05.",
        "Rolled back the 14:00 deploy of payments-api.",
        "Errors stopped, checkout is healthy again."
      ].freeze

      STEPS = {
        1 => {
          title: ":compass:  *Your first incident. Step 1 of 4*",
          body: "Make yourself the lead. Click the button or run `/ff lead`. The announcement in %{channel} updates as you go.",
          fallback: "Your first incident. Step 1 of 4: make yourself the lead.",
          button: { text: ":firefighter: Make me Lead", action_id: Identifiers::SET_INCIDENT_LEAD_SELF }
        },
        2 => {
          title: ":white_check_mark:  *Nice. Step 2 of 4*",
          body: "Post a few messages about what is happening. The postmortem is drafted from them. Paste these if you like:\n```\n#{SCRIPT.join("\n")}\n```",
          fallback: "Step 2 of 4: post a few messages about what is happening."
        },
        3 => {
          title: ":white_check_mark:  *Good. Step 3 of 4*",
          body: "Resolve the incident when it is fixed. Click the button or run `/ff resolve`.",
          fallback: "Step 3 of 4: resolve the incident when it is fixed.",
          button: { text: ":white_check_mark: Resolve", action_id: Identifiers::RESOLVE_INCIDENT }
        },
        4 => {
          title: ":white_check_mark:  *Resolved. Step 4 of 4*",
          body: "Click *Write the postmortem* in the message just above, or run `/ff postmortem`. Firefight drafts it from the timeline and your messages.",
          fallback: "Step 4 of 4: write the postmortem."
        },
        5 => {
          title: ":tada:  *That is the whole loop*",
          body: "Your postmortem is pinned here and open in the dashboard. Next, share %{channel} with your team from the welcome message there, so they can declare incidents too. Every command is in the <#{COMMANDS_DOCS_URL}|command reference>. Your AI agents can work incidents as well, over MCP. <#{MCP_DOCS_URL}|Connect one>.",
          fallback: "That is the whole loop. Share #incidents with your team next. Command reference: #{COMMANDS_DOCS_URL} Connect an AI agent: #{MCP_DOCS_URL}"
        }
      }.freeze

      # Steps 1 and 3 carry their button. Step 4 does not, the resolution
      # message directly above it already has one.
      def self.build(incident, step:)
        copy = STEPS.fetch(step)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: copy[:title] } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: format(copy[:body], channel: announcements_channel(incident)) } }
        ]
        if copy[:button]
          blocks << {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: copy[:button][:text], emoji: true },
                action_id: copy[:button][:action_id],
                value: incident.id,
                style: "primary"
              }
            ]
          }
        end
        blocks
      end

      def self.fallback_text(step)
        STEPS.fetch(step)[:fallback]
      end

      def self.announcements_channel(incident)
        channel_id = incident.workspace.incidents_channel_id
        channel_id.present? ? "<##{channel_id}>" : "#incidents"
      end
    end
  end
end
