module Slack
  module Modals
    module Home
      COMMAND_HELP = {
        "new" => "*Create a new incident*\n\nUsage: `/ff new`\nOpens the incident creation form.",
        "summary" => "*Update incident summary*\n\nUsage: `/ff summary`\nUpdate the current understanding of the incident.",
        "lead" => "*Set incident lead*\n\nUsage: `/ff lead`\nAssign an incident lead to coordinate response.",
        "roles" => "*Assign incident roles*\n\nUsage: `/ff roles`\nAssign every incident role, one person each.",
        "status" => "*Update status*\n\nUsage: `/ff status`\nChange the incident status (e.g., Investigating, Identified, Monitoring).",
        "severity" => "*Change severity*\n\nUsage: `/ff severity [critical|major|minor]`\nEscalate or de-escalate the incident severity.",
        "escalate" => "*Escalate to someone*\n\nUsage: `/ff escalate`\nPage or notify someone about this incident.",
        "invite" => "*Invite responders*\n\nUsage: `/ff invite @user1 @user2`\nInvites responders into the current incident channel. Run `/ff invite` without users to open a picker.",
        "actions" => "*Manage actions*\n\nUsage: `/ff actions`\nView, create, and complete incident action items.",
        "close" => "*Close incident*\n\nUsage: `/ff close` or `/ff resolve`\nMark the incident as resolved.",
        "cancel" => "*Cancel incident*\n\nUsage: `/ff cancel`\nDismiss a false positive, duplicate, or test. Keeps it out of resolution metrics.",
        "postmortem" => "*Generate postmortem*\n\nUsage: `/ff postmortem`\nGenerate a postmortem document from the incident timeline.",
        "timeline" => "*View timeline*\n\nUsage: `/ff timeline`\nSee the full history of incident events.",
        "list" => "*List active incidents*\n\nUsage: `/ff list`\nShow all currently open incidents.",
        "catchup" => "*AI incident catchup*\n\nUsage: `/ff catchup`\nGet an AI-generated summary of the current incident."
      }.freeze

      def self.build(channel_id:)
        {
          type: "modal",
          callback_id: Identifiers::INCIDENT_HOME_MODAL,
          private_metadata: ModalState.encode(channel_id: channel_id),
          title: { type: "plain_text", text: "Incident Home" },
          submit: { type: "plain_text", text: "Continue" },
          close: { type: "plain_text", text: "Close" },
          blocks: [
            {
              type: "input",
              dispatch_action: true,
              block_id: "action_select_block",
              element: {
                type: "static_select",
                action_id: Identifiers::HOME_ACTION_SELECT,
                placeholder: { type: "plain_text", text: "Type a command or search..." },
                option_groups: option_groups
              },
              label: { type: "plain_text", text: "Choose an action" },
              hint: { type: "plain_text", text: "Search and run any Firefight action from one place." }
            },
            {
              type: "section",
              block_id: "command_details_block",
              text: {
                type: "mrkdwn",
                text: "*For example:*\n\n:pencil2:  Update the current status or severity `/ff status`\n\n:rotating_light:  Escalate to someone who can help `/ff escalate`\n\n:dart:  Assign the incident lead role `/ff lead`\n\n:lock:  Close the incident when it's resolved `/ff close`"
              }
            }
          ]
        }
      end

      def self.option_groups
        [
          {
            label: { type: "plain_text", text: "Quick actions", emoji: true },
            options: [
              { text: { type: "plain_text", text: ":pencil2: Update status",           emoji: true }, value: Identifiers::HOME_ACTION_STATUS },
              { text: { type: "plain_text", text: ":warning: Change severity",         emoji: true }, value: Identifiers::HOME_ACTION_SEVERITY },
              { text: { type: "plain_text", text: ":memo: Update incident summary",    emoji: true }, value: Identifiers::HOME_ACTION_SUMMARY }
            ]
          },
          {
            label: { type: "plain_text", text: "Communicate", emoji: true },
            options: [
              { text: { type: "plain_text", text: ":rotating_light: Escalate to someone", emoji: true }, value: Identifiers::HOME_ACTION_ESCALATE },
              { text: { type: "plain_text", text: ":busts_in_silhouette: Invite responders", emoji: true }, value: Identifiers::HOME_ACTION_INVITE }
            ]
          },
          {
            label: { type: "plain_text", text: "Coordinate", emoji: true },
            options: [
              { text: { type: "plain_text", text: ":dart: Set incident lead", emoji: true }, value: Identifiers::HOME_ACTION_LEAD },
              { text: { type: "plain_text", text: ":busts_in_silhouette: Assign incident roles", emoji: true }, value: Identifiers::HOME_ACTION_ROLES },
              { text: { type: "plain_text", text: ":ballot_box_with_check: Manage actions", emoji: true }, value: Identifiers::HOME_ACTION_ACTIONS },
              { text: { type: "plain_text", text: ":book: Attach runbook",   emoji: true }, value: Identifiers::HOME_ACTION_RUNBOOK },
              { text: { type: "plain_text", text: ":lock: Close incident",    emoji: true }, value: Identifiers::HOME_ACTION_CLOSE }
            ]
          },
          {
            label: { type: "plain_text", text: "Review", emoji: true },
            options: [
              { text: { type: "plain_text", text: ":clock1: View timeline",              emoji: true }, value: Identifiers::HOME_ACTION_TIMELINE },
              { text: { type: "plain_text", text: ":clipboard: List active incidents",   emoji: true }, value: Identifiers::HOME_ACTION_LIST },
              { text: { type: "plain_text", text: ":page_facing_up: Generate postmortem", emoji: true }, value: Identifiers::HOME_ACTION_POSTMORTEM }
            ]
          },
          {
            label: { type: "plain_text", text: "New", emoji: true },
            options: [
              { text: { type: "plain_text", text: ":fire: Create a new incident", emoji: true }, value: Identifiers::HOME_ACTION_NEW }
            ]
          }
        ]
      end

      def self.command_help(command)
        COMMAND_HELP[command] || "_Select an action above to see how to use the command directly._"
      end
    end
  end
end
