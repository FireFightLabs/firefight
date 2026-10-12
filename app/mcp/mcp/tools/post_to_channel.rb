module Mcp
  module Tools
    class PostToChannel < Base
      tool_name POST_TO_CHANNEL
      authorize_as Ability::Action::RESOURCE_CHANNEL_POSTS, Ability::Action::ACTION_CREATE
      description "Post a message as Firefight in any channel it can post in, such as release notes in #general or a " \
                  "heads up to a team's channel. The post names who asked for it. Use post_incident_update for an " \
                  "incident's own channel. Name the channel by its name, its id or its link. A private channel needs " \
                  "Firefight invited to it first and is named by its link or id. Write message as markdown with real " \
                  "line breaks, links as plain URLs or [text](url) and one \"- \" bullet per point. Mentions such as " \
                  "@here are shown as written and notify nobody. If the call requires approval, retry the identical " \
                  "call with approval_id once approved. Docs: #{Docs::PERMISSIONS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          channel: { type: "string", description: "The channel, such as #general, or its id or link" },
          message: { type: "string", description: "What to post, as markdown, at most #{ChannelPostService::MESSAGE_LIMIT} characters" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "channel", "message" ]
      )

      names_halon

      def self.perform_with_principal(workspace:, principal:, args:, by_halon: false)
        posted = ChannelPostService.new(workspace).post!(channel: args[:channel], message: args[:message].to_s, by: principal, by_halon: by_halon)
        respond(posted: true, channel: posted.channel_name ? "##{posted.channel_name}" : args[:channel].to_s, channel_id: posted.channel_id, link: posted.link)
      rescue ChannelPostService::Refused => refused
        Mcp::ToolDispatcher.error_response(refused.message)
      end
    end
  end
end
