module Integrations
  module HealthProbes
    # Lists Honeybadger's projects through list_projects, which only works with a sign in Honeybadger accepts, and keeps
    # each one's id and name, so a service on the map finds the project its errors go to, and, through get_project, the
    # uptime sites each project checks. Only ids, names and addresses are kept, never a project's API key. The tools and
    # their answers are from honeybadger-io/honeybadger-mcp-server (internal/hbmcp/projects.go) and honeybadger-io/api-go
    # (projects.go, types.go).
    class Honeybadger < RemoteReader
      LIST_PROJECTS = "list_projects".freeze
      GET_PROJECT = "get_project".freeze
      # Each project's sites cost a call, so a check reads at most this many projects.
      MAX_PROJECTS = 25

      def self.projects(settings) = Array(settings&.learned.to_h["projects"])

      def check!
        result = call(LIST_PROJECTS)
        return if result.nil?
        refused!(LIST_PROJECTS, result)

        body = Capabilities::Answers.data(result)
        raise Refused, "Honeybadger answered its projects in a shape Firefight does not read." unless body.is_a?(Hash) && body["results"].is_a?(Array)

        projects = body["results"].filter_map { |project| { "id" => project["id"], "name" => project["name"] } if project.is_a?(Hash) && project["id"] }
        projects.first(MAX_PROJECTS).each { |project| project["sites"] = sites(project["id"]) }
        { "projects" => projects }
      end

      private

      # A project's uptime sites. None when get_project is off, refuses, or answers in a shape Firefight does not read.
      def sites(id)
        result = call(GET_PROJECT, { "id" => id })
        body = result && !result["isError"] ? Capabilities::Answers.data(result) : nil
        return [] unless body.is_a?(Hash)

        Array(body["sites"]).filter_map { |site| { "id" => site["id"], "name" => site["name"], "url" => site["url"] } if site.is_a?(Hash) && site["url"].present? }
      end
    end
  end
end
