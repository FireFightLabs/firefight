module Integrations
  module IssueTrackers
    # Atlassian's server opens an issue with createjiraissue, whose answer names the new key, and moves one with
    # transitionjiraissue, whose answer does not say where it moved. So a transition is followed by Firefight's own read
    # of the issue with getjiraissue, and the issue is closed when its status is in Jira's done category (statusCategory
    # key done, which every Jira workflow's finished statuses carry). The page is https://<site>/browse/<KEY>, the
    # address Atlassian's agent skills give (see SourceLinks::Jira). The site is the call's cloudId when it names the
    # site, or else the address getaccessibleatlassianresources gives for that cloud id.
    class Jira < RemoteReader
      CREATE_ISSUE = SourceLinks::Jira::CREATE_ISSUE
      TRANSITION_ISSUE = "transitionjiraissue".freeze
      GET_ISSUE = "getjiraissue".freeze
      RESOURCES = "getaccessibleatlassianresources".freeze
      DONE = "done".freeze
      READ_FIELDS = %w[summary status].freeze

      def report(tool_name:, arguments:, result:)
        case tool_name
        when CREATE_ISSUE then opened(arguments, result)
        when TRANSITION_ISSUE then closed(arguments)
        end
      end

      private

      def opened(arguments, result)
        key = Capabilities::Answers.text(result)[SourceLinks::Jira::CREATED_KEY, 1]
        url = key && page(arguments[SourceLinks::Jira::CLOUD_ID], key)
        return unless url

        Issues::Report.new(change: Issues::OPENED, key: key, title: arguments["summary"].to_s.strip.presence, url: url)
      end

      def closed(arguments)
        key = arguments[SourceLinks::Jira::ISSUE].to_s.strip
        return unless key.match?(SourceLinks::Jira::ISSUE_KEY)

        issue = read_issue(arguments[SourceLinks::Jira::CLOUD_ID], key)
        return unless issue&.dig("fields", "status", "statusCategory", "key") == DONE

        url = page(arguments[SourceLinks::Jira::CLOUD_ID], key)
        url && Issues::Report.new(change: Issues::CLOSED, key: key, title: issue.dig("fields", "summary").presence, url: url)
      end

      def read_issue(cloud_id, key)
        asked = { SourceLinks::Jira::CLOUD_ID => cloud_id, SourceLinks::Jira::ISSUE => key }
        fields = parameters(GET_ISSUE)["fields"]
        asked["fields"] = fields.to_h["type"] == "string" ? READ_FIELDS.join(",") : READ_FIELDS if fields
        result = call(GET_ISSUE, asked, "the status of #{key}")
        data = result && !result["isError"] ? Capabilities::Answers.data(result) : nil
        data.is_a?(Hash) ? data : nil
      end

      def page(cloud_id, key)
        site = SourceLinks::Jira.site_of(cloud_id) || site_of_resource(cloud_id)
        site && "https://#{site}/browse/#{key}"
      end

      def site_of_resource(cloud_id)
        return if cloud_id.blank?

        result = call(RESOURCES, {}, "the address of the Jira site")
        resources = result && !result["isError"] ? Capabilities::Answers.data(result) : nil
        found = Array(resources).find { |resource| resource.is_a?(Hash) && resource["id"] == cloud_id.to_s }
        found && SourceLinks::Jira.site_of(found["url"])
      end
    end
  end
end
