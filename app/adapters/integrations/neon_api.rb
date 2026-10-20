module Integrations
  # Calls to the Neon API (https://console.neon.tech/api/v2, api-docs.neon.tech) with a connection's own organization API
  # key, sent as Bearer as the API's BearerAuth scheme says. A failure says why in its message field (GeneralError).
  class NeonApi
    class Error < Integrations::Error; end
    # The key is wrong, reaches no such project or organization, or the plan does not include what was asked.
    class Refused < Error; end

    ROOT = "https://console.neon.tech/api/v2".freeze
    REFUSALS = [ 401, 403 ].freeze

    # authorization is the Authorization header the connection holds.
    def initialize(authorization)
      @authorization = authorization
    end

    # One project (ProjectResponse), which says the organization it is in.
    def project(project_id) = request(:get, "/projects/#{Http.segment(project_id)}")["project"].to_h

    # One branch (BranchResponse), for its name and parent.
    def branch(project_id, branch_id) = request(:get, "/projects/#{Http.segment(project_id)}/branches/#{Http.segment(branch_id)}")["branch"].to_h

    # Restores a branch to a moment or a point of its own or another branch's history (restoreProjectBranch,
    # BranchRestoreRequest), answering the branch and the operations it started (BranchOperations).
    def restore_branch(project_id, branch_id, body)
      request(:post, "/projects/#{Http.segment(project_id)}/branches/#{Http.segment(branch_id)}/restore", body: body)
    end

    # A project's consumption over a range (getConsumptionHistoryPerProjectV2), the periods of the one project asked for.
    def consumption(org_id:, project_id:, from:, to:, granularity:, metrics:)
      query = { "org_id" => org_id, "project_ids" => project_id, "from" => from, "to" => to, "granularity" => granularity,
                "metrics" => metrics.join(",") }
      request(:get, "/consumption_history/v2/projects", query: query)["projects"].to_a.find { |each| each["project_id"] == project_id }.to_h
    end

    private

    def request(verb, path, query: nil, body: nil)
      uri = URI.parse("#{ROOT}#{path}")
      uri.query = URI.encode_www_form(query) if query
      request = verb == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      request["Authorization"] = @authorization
      request["Accept"] = "application/json"
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      Http.json(uri, request, error_class: Error, provider_name: "Neon", refine: ->(code, _said) { Refused if REFUSALS.include?(code) })
    end
  end
end
