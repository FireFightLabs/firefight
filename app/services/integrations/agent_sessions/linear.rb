module Integrations
  module AgentSessions
    # Linear's agents (linear.app/developers/agents and /agent-interaction). Firefight's app is installed with actor=app, so
    # it is a user of its own that people delegate an issue to or mention, and each time Linear opens an Agent Session and
    # sends an AgentSessionEvent to the OAuth application's own webhook, which every organization that installed it shares.
    # Its fields are AgentSessionEventWebhookPayload in the SDK's schema.graphql (linear/linear, packages/sdk/src):
    #   created     a new session, with agentSession (its id, issue, the comment that mentioned the app and the creator)
    #               and promptContext, Linear's own account of the issue, its comments and the team's guidance
    #   prompted    a follow up, its words in agentActivity's content body, and a stop request when agentActivity's signal
    #               is stop (linear.app/developers/agent-signals)
    # Two more categories of the same webhook say what changed about the installation (linear.app/developers/
    # agent-best-practices, Additional webhooks): PermissionChange (teamAccessChanged) when an admin changes the teams the
    # app may reach, and OAuthApp (revoked) when the app is removed. Every delivery names organizationId, the installation,
    # and is signed like any Linear webhook (IssueTrackers::Linear.verify). Anything else is left alone.
    #
    # Halon answers through agentActivityCreate: a thought within ten seconds of created, or the session reads as
    # unresponsive, action for each tool, then response or error, and elicitation for what needs a person. Each body is
    # Markdown. An elicitation with choices carries the select signal, its options in signalMetadata, and Linear sends
    # the one picked back as a prompted activity (linear.app/developers/agent-signals, select).
    class Linear
      TYPE_SESSION = "AgentSessionEvent".freeze
      TYPE_PERMISSION = "PermissionChange".freeze
      TYPE_APP = "OAuthApp".freeze
      TYPE_ISSUE = "Issue".freeze
      ACTION_CREATE = "create".freeze
      ACTION_UPDATE = "update".freeze
      ACTION_CREATED = "created".freeze
      ACTION_PROMPTED = "prompted".freeze
      ACTION_REVOKED = "revoked".freeze
      ACTION_TEAM_ACCESS = "teamAccessChanged".freeze
      SIGNAL_STOP = "stop".freeze
      SIGNAL_SELECT = "select".freeze

      class << self
        def verify(raw_body:, headers:, secret:) = IssueTrackers::Linear.verify(raw_body: raw_body, headers: headers, secret: secret)

        def installation_of(payload, headers: nil) = payload["organizationId"].presence

        def installation_change(payload, headers: nil)
          case [ payload["type"], payload["action"] ]
          when [ TYPE_APP, ACTION_REVOKED ] then Installations::CHANGE_REMOVED
          when [ TYPE_PERMISSION, ACTION_TEAM_ACCESS ] then Installations::CHANGE_REACH
          end
        end

        # An Issues data change event (linear.app/developers/webhooks, Data change events), which the app's webhook
        # receives once the operator ticks Issues, names the issue's labels in data (labelIds, and labels with their
        # names) and the ones it had before a change in updatedFrom. A label is added when an issue is made with it or
        # when an update's labelIds holds it and updatedFrom's did not. An update that left the labels alone has no
        # labelIds in updatedFrom. actor is who did it.
        def labelled(payload)
          issue = payload["data"]
          return unless payload["type"] == TYPE_ISSUE && issue.is_a?(Hash) && issue["id"].present?

          before = case payload["action"]
          when ACTION_CREATE then []
          when ACTION_UPDATE then payload.dig("updatedFrom", "labelIds")
          end
          return unless before.is_a?(Array)

          added = Array(issue["labels"]).select { |label| label.is_a?(Hash) && Array(issue["labelIds"]).include?(label["id"]) && before.exclude?(label["id"]) }
          names = added.filter_map { |label| label["name"].presence }
          return if names.empty?

          AgentSessions::Labelled.new(
            reference: "#{issue['id']}:#{added.map { |label| label['id'] }.sort.join(',')}:#{issue['updatedAt']}", labels: names,
            issue_key: issue["identifier"].presence, issue_title: issue["title"].presence, issue_url: (issue["url"] || payload["url"]).presence,
            text: issue["description"].presence, **asker_of(payload["actor"])
          )
        end

        def event(payload)
          session = payload["agentSession"]
          return unless payload["type"] == TYPE_SESSION && session.is_a?(Hash) && session["id"].present?

          case payload["action"]
          when ACTION_CREATED then started(payload, session)
          when ACTION_PROMPTED then prompted(payload, session)
          end
        end

        private

        def started(payload, session)
          AgentSessions::Event.new(
            kind: STARTED, session_id: session["id"], text: session.dig("comment", "body").presence, context: payload["promptContext"].presence,
            **issue_of(session), **asker_of(session["creator"])
          )
        end

        def prompted(payload, session)
          activity = payload["agentActivity"].to_h
          return AgentSessions::Event.new(kind: STOPPED, session_id: session["id"], **issue_of(session)) if activity["signal"] == SIGNAL_STOP

          text = (activity.dig("content", "body") || activity["body"]).to_s.strip.presence
          return unless text

          AgentSessions::Event.new(kind: PROMPTED, session_id: session["id"], text: text, **issue_of(session), **asker_of(activity["user"]))
        end

        def issue_of(session)
          issue = session["issue"].to_h
          { issue_key: issue["identifier"].presence, issue_title: issue["title"].presence, issue_url: issue["url"].presence }
        end

        def asker_of(user) = { asker_email: user.to_h["email"].presence, asker_name: user.to_h["name"].presence }
      end

      def initialize(environment_row)
        @environment_row = environment_row
      end

      def say(session_id, activity)
        content = { "type" => activity.kind, "body" => activity.body, "action" => activity.action, "parameter" => activity.parameter,
                    "result" => activity.result }.compact
        input = { "agentSessionId" => session_id, "content" => content }
        input["ephemeral"] = true if activity.ephemeral
        if activity.choices.any?
          input["signal"] = SIGNAL_SELECT
          input["signalMetadata"] = { "options" => activity.choices.map { |choice| { "label" => choice, "value" => choice } } }
        end
        api.create_activity(input)
      rescue LinearApi::Error => error
        raise Integrations::Error, error.message
      end

      private

      def api = @api ||= LinearApi.new(Credentials.headers_for(@environment_row))
    end
  end
end
