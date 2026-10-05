module Integrations
  module Packs
    # Linear connected with Firefight's own OAuth application, for keeping incident items in step with issues. Its tools
    # carry the names and arguments of Linear's hosted MCP server's (save_issue, get_issue, list_issue_statuses,
    # list_users) and answer the issue in the shape that server does, so IssueTrackers::Linear reads either connection
    # the same way. It also registers the webhook that sends changes back, through webhookCreate, which Linear allows an
    # OAuth application holding the admin scope (linear.app/developers/webhooks). Every call is LinearApi's.
    class Linear < NativePack
      PROVIDER = "Linear".freeze
      TEAM = IssueTrackers::Linear::TEAM
      ISSUE_RESOURCE = "Issue".freeze
      WEBHOOK_LABEL = "Firefight".freeze

      ISSUE_ID = { "type" => "string", "description" => "The issue's identifier, such as ENG-12" }.freeze

      tool :save_issue,
           description: "Open a Linear issue when no id is given, or change the one the id names. team is the key or name of the " \
                        "team to open it in. assignee and state are ids, from list_users and list_issue_statuses, and an " \
                        "assignee of null unassigns it",
           params_schema: {
             "type" => "object",
             "properties" => {
               "id" => ISSUE_ID, "title" => { "type" => "string" }, "description" => { "type" => "string" },
               "team" => { "type" => "string" }, "assignee" => { "type" => [ "string", "null" ] }, "state" => { "type" => "string" }
             }
           },
           read_only: false

      tool :get_issue,
           description: "One Linear issue by its identifier, with its title, state and assignee",
           params_schema: { "type" => "object", "properties" => { "id" => ISSUE_ID }, "required" => [ "id" ] },
           read_only: true

      tool :list_issue_statuses,
           description: "The workflow states of a Linear team, by its key or name, each with its id, name and type",
           params_schema: { "type" => "object", "properties" => { "team" => { "type" => "string" } }, "required" => [ "team" ] },
           read_only: true

      tool :list_users,
           description: "The Linear people whose email is the query, each with their id, name and email",
           params_schema: { "type" => "object", "properties" => { "query" => { "type" => "string" } }, "required" => [ "query" ] },
           read_only: true

      def save_issue(environment_row:, arguments:)
        api = api(environment_row)
        input = { "title" => arguments["title"], "description" => arguments["description"], "stateId" => arguments["state"] }.compact
        input["assigneeId"] = arguments["assignee"] if arguments.key?("assignee")
        issue = if arguments["id"].present?
          api.update_issue(arguments["id"], input)
        else
          team = team!(api, arguments[TEAM])
          api.create_issue(input.merge("teamId" => team["id"]))
        end
        answer(shaped(issue))
      rescue LinearApi::Error => error
        refused(error)
      end

      def get_issue(environment_row:, arguments:)
        answer(shaped(api(environment_row).issue(arguments["id"].to_s)))
      rescue LinearApi::Error => error
        refused(error)
      end

      def list_issue_statuses(environment_row:, arguments:)
        api = api(environment_row)
        answer(api.states(team!(api, arguments[TEAM])["id"]).sort_by { |state| state["position"].to_f })
      rescue LinearApi::Error => error
        refused(error)
      end

      def list_users(environment_row:, arguments:)
        answer(api(environment_row).users_by_email(arguments["query"].to_s.strip))
      rescue LinearApi::Error => error
        refused(error)
      end

      def check_health!(environment_row)
        api(environment_row).viewer
      rescue LinearApi::Error => error
        fail! error.message
      end

      # A webhook on the team issues go to, signed with a secret Firefight makes (WebhookCreateInput.secret).
      def register_issue_webhook(environment_row, url:, target:)
        api = api(environment_row)
        secret = SecureRandom.hex(32)
        webhook = api.create_webhook(
          "url" => url, "teamId" => team!(api, target.to_h[TEAM])["id"], "resourceTypes" => [ ISSUE_RESOURCE ], "secret" => secret,
          "label" => WEBHOOK_LABEL
        )
        raise Issues::Failed, "Linear did not register the webhook." unless webhook&.dig("id")

        Issues::Webhook.new(id: webhook["id"], secret: secret)
      rescue LinearApi::Error => error
        raise Issues::Failed, error.message
      end

      def remove_issue_webhook(environment_row, id)
        api(environment_row).delete_webhook(id)
      rescue LinearApi::Error => error
        raise Issues::Failed, error.message
      end

      private

      def api(environment_row) = LinearApi.new(Credentials.headers_for(environment_row))

      def team!(api, key_or_name)
        name = key_or_name.to_s.strip
        raise LinearApi::Error, "Choose the Linear team new issues are filed in under Settings, Workspace." if name.empty?

        api.team(name) || raise(LinearApi::Error, "Linear has no team called #{name}.")
      end

      # The issue as Linear's MCP server answers it, its identifier as its id and its state's type as statusType.
      def shaped(issue)
        return {} unless issue

        { "id" => issue["identifier"], "identifier" => issue["identifier"], "title" => issue["title"], "url" => issue["url"],
          "statusType" => issue.dig("state", "type"), "status" => issue.dig("state", "name"), "assignee" => issue["assignee"] }.compact
      end

      def answer(data) = { "content" => [ { "type" => "text", "text" => data.to_json } ] }

      def refused(error) = { "isError" => true, "content" => [ { "type" => "text", "text" => error.message } ] }
    end
  end
end
