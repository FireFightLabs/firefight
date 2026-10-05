module Integrations
  module Packs
    # Jira connected with Firefight's own OAuth 2.0 (3LO) app, for keeping incident items in step with issues. Its tools
    # carry the names and arguments of Atlassian's MCP server's (createjiraissue, editjiraissue, transitionjiraissue,
    # listjiraissuetransitions, lookupjiraaccountid, getjiraissue), each taking the site's address as cloudId, so
    # IssueTrackers::Jira reads either connection the same way. It also registers the dynamic webhook that sends changes
    # back and refreshes it before Jira lets it lapse. Every call is JiraApi's.
    class Jira < NativePack
      CLOUD = SourceLinks::Jira::CLOUD_ID
      ISSUE = SourceLinks::Jira::ISSUE
      FIELDS = %w[summary status assignee].freeze
      # Jira lets a webhook an app registered lapse after this long unless it is refreshed.
      LIFETIME = 30.days
      # The site the webhook was registered on, kept with the connection's credentials.
      WEBHOOK_SITE = "webhook_site".freeze

      SITE_ARG = { "type" => "string", "description" => "The Jira site's address, such as acme.atlassian.net" }.freeze
      ISSUE_ARG = { "type" => "string", "description" => "The issue's key, such as OPS-42" }.freeze
      ON_ISSUE = { "type" => "object", "properties" => { CLOUD => SITE_ARG, ISSUE => ISSUE_ARG }, "required" => [ CLOUD, ISSUE ] }.freeze

      tool :createjiraissue,
           description: "Open a Jira issue in a project, with its type, summary, description and, optionally, the account id to assign",
           params_schema: {
             "type" => "object",
             "properties" => {
               CLOUD => SITE_ARG, "projectKey" => { "type" => "string" }, "issueType" => { "type" => "string" },
               "summary" => { "type" => "string" }, "description" => { "type" => "string" }, "assignee" => { "type" => "string" }
             },
             "required" => [ CLOUD, "projectKey", "issueType", "summary" ]
           },
           read_only: false

      tool :editjiraissue,
           description: "Change a Jira issue's fields, such as summary, or assignee as an object with an accountId, null to unassign",
           params_schema: ON_ISSUE.deep_merge("properties" => { "fields" => { "type" => "object" } }, "required" => [ CLOUD, ISSUE, "fields" ]),
           read_only: false

      tool :transitionjiraissue,
           description: "Move a Jira issue through one of its transitions, given as an object with its id",
           params_schema: ON_ISSUE.deep_merge("properties" => { "transition" => { "type" => "object" } }, "required" => [ CLOUD, ISSUE, "transition" ]),
           read_only: false

      tool :listjiraissuetransitions,
           description: "The transitions a Jira issue can take now, each with the status it leads to and that status's category",
           params_schema: ON_ISSUE,
           read_only: true

      tool :lookupjiraaccountid,
           description: "The Jira accounts matching a name or an email, each with its account id and, where its profile shows it, its email",
           params_schema: { "type" => "object", "properties" => { CLOUD => SITE_ARG, "query" => { "type" => "string" } }, "required" => [ CLOUD, "query" ] },
           read_only: true

      tool :getjiraissue,
           description: "One Jira issue by its key, with its summary, status and assignee",
           params_schema: ON_ISSUE,
           read_only: true

      def createjiraissue(environment_row:, arguments:)
        answering(environment_row, arguments) do |api, cloud|
          fields = {
            "project" => { "key" => arguments["projectKey"] }, "issuetype" => { "name" => arguments["issueType"] },
            "summary" => arguments["summary"], "description" => document(arguments["description"]),
            "assignee" => (arguments["assignee"].presence && { "accountId" => arguments["assignee"] })
          }.compact
          api.create_issue(cloud, fields)
        end
      end

      def editjiraissue(environment_row:, arguments:)
        answering(environment_row, arguments) do |api, cloud|
          api.edit_issue(cloud, arguments[ISSUE], arguments["fields"].to_h)
          "Updated #{arguments[ISSUE]}."
        end
      end

      def transitionjiraissue(environment_row:, arguments:)
        answering(environment_row, arguments) do |api, cloud|
          api.transition(cloud, arguments[ISSUE], arguments.dig("transition", "id").to_s)
          "Moved #{arguments[ISSUE]}."
        end
      end

      def listjiraissuetransitions(environment_row:, arguments:)
        answering(environment_row, arguments) { |api, cloud| api.transitions(cloud, arguments[ISSUE]) }
      end

      def lookupjiraaccountid(environment_row:, arguments:)
        answering(environment_row, arguments) { |api, cloud| api.users(cloud, arguments["query"].to_s.strip) }
      end

      def getjiraissue(environment_row:, arguments:)
        answering(environment_row, arguments) { |api, cloud| api.issue(cloud, arguments[ISSUE], FIELDS) }
      end

      def check_health!(environment_row)
        fail! "Firefight's Jira app reaches no Jira site." if api(environment_row).resources.empty?
      rescue JiraApi::Error => error
        fail! error.message
      end

      # A dynamic webhook on the project's issues. Jira signs what it sends with the app's client secret, so there is no
      # secret of the webhook's own to keep.
      def register_issue_webhook(environment_row, url:, target:)
        api = api(environment_row)
        site = SourceLinks::Jira.site_of(target.to_h[IssueTrackers::Jira::SITE])
        project = target.to_h[IssueTrackers::Jira::PROJECT].to_s.strip.upcase
        raise Issues::Failed, "Choose the Jira site and project new issues are filed in under Settings, Workspace." if site.nil? || project.empty?

        cloud = api.cloud_id(site)
        id = api.register_webhook(cloud, url, %(project = "#{project}"))
        ConnectionSettings.of(environment_row).store_credential!(WEBHOOK_SITE, site)
        Issues::Webhook.new(id: id.to_s, expires_at: LIFETIME.from_now)
      rescue JiraApi::Error => error
        raise Issues::Failed, error.message
      end

      def remove_issue_webhook(environment_row, id)
        api = api(environment_row)
        api.delete_webhook(api.cloud_id(webhook_site(environment_row)), id)
      rescue JiraApi::Error => error
        raise Issues::Failed, error.message
      end

      def refresh_issue_webhook(environment_row, id)
        api = api(environment_row)
        expires = api.refresh_webhook(api.cloud_id(webhook_site(environment_row)), id)
        expires.present? ? Time.zone.parse(expires.to_s) : LIFETIME.from_now
      rescue JiraApi::Error => error
        raise Issues::Failed, error.message
      end
      private

      def api(environment_row) = JiraApi.new(Credentials.headers_for(environment_row))

      def webhook_site(environment_row) = ConnectionSettings.of(environment_row).credential(WEBHOOK_SITE)

      # Runs the call on the site the arguments name, answering what Jira gave as the tool's answer, or Jira's refusal
      # as an error answer so a missing issue reads as one.
      def answering(environment_row, arguments)
        api = api(environment_row)
        site = SourceLinks::Jira.site_of(arguments[CLOUD])
        return refused("Give the Jira site's address as cloudId.") unless site

        answer = yield api, api.cloud_id(site)
        { "content" => [ { "type" => "text", "text" => answer.is_a?(String) ? answer : answer.to_json } ] }
      rescue JiraApi::Error => error
        refused(error.message)
      end

      def refused(text) = { "isError" => true, "content" => [ { "type" => "text", "text" => text } ] }

      # Jira's REST API v3 takes a description as an Atlassian Document, a paragraph per line, an address as a link.
      def document(text)
        return nil if text.blank?

        paragraphs = text.to_s.split(/\n{2,}/).map do |line|
          node = { "type" => "text", "text" => line }
          node["marks"] = [ { "type" => "link", "attrs" => { "href" => line } } ] if line.match?(%r{\Ahttps?://\S+\z})
          { "type" => "paragraph", "content" => [ node ] }
        end
        { "type" => "doc", "version" => 1, "content" => paragraphs }
      end
    end
  end
end
