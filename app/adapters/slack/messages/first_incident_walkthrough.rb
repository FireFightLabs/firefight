module Slack
  module Messages
    # The coach in the channel of a workspace's first test incident. One step
    # at a time, each posted as the previous one is done, so the responder is
    # never asked to scroll up and work through a list.
    module FirstIncidentWalkthrough
      SCRIPT = [
        "Customers are seeing 502s on checkout since 14:05.",
        "Rolled back the 14:00 deploy of payments-api.",
        "Errors stopped, checkout is healthy again."
      ].freeze

      STEPS = {
        1 => {
          title: ":compass:  *Your first incident. Step 1 of 4*",
          body: "Click *Make me Lead* above. The announcement in %{channel} updates as you go.",
          fallback: "Your first incident. Step 1 of 4: click Make me Lead."
        },
        2 => {
          title: ":white_check_mark:  *Nice. Step 2 of 4*",
          body: "Post a few messages about what is happening. The postmortem is drafted from them. Paste these if you like:\n```\n#{SCRIPT.join("\n")}\n```",
          fallback: "Step 2 of 4: post a few messages about what is happening."
        },
        3 => {
          title: ":white_check_mark:  *Good. Step 3 of 4*",
          body: "Click *Resolve* above when it is fixed.",
          fallback: "Step 3 of 4: click Resolve when it is fixed."
        },
        4 => {
          title: ":white_check_mark:  *Resolved. Step 4 of 4*",
          body: "Click *Write the postmortem* above. Firefight drafts it from the timeline and your messages.",
          fallback: "Step 4 of 4: click Write the postmortem."
        },
        5 => {
          title: ":tada:  *That is the whole loop*",
          body: "Your postmortem is pinned here and open in the dashboard. Next, share %{channel} with your team from the welcome message there, so they can declare incidents too.",
          fallback: "That is the whole loop. Share #incidents with your team next."
        }
      }.freeze

      def self.build(incident, step:)
        copy = STEPS.fetch(step)
        [
          { type: "section", text: { type: "mrkdwn", text: copy[:title] } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: format(copy[:body], channel: announcements_channel(incident)) } }
        ]
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
