module Integrations
  # Calls to PlanetScale's REST API (api.planetscale.com/v1) for what its MCP server has no tool for, with the PlanetScale
  # connection's own credentials. Paths, parameters and fields are the ones in PlanetScale's OpenAPI description
  # (api.planetscale.com/v1/openapi-spec). authorization is the Authorization header as PlanetScale's API takes it: an
  # OAuth access token as Bearer, or a service token as <id>:<secret> (planetscale.com/docs/api/reference/oauth and
  # /service-tokens).
  class PlanetscaleApi
    class Error < Integrations::Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # PlanetScale turned the request down for what the token may do or what the call asked, as opposed to failing.
    class Refused < Error; end
    REFINED = { 401 => Refused, 403 => Refused, 404 => NotFound, 422 => Refused }.freeze

    API_ROOT = "https://api.planetscale.com/v1".freeze
    PER_PAGE = 100
    MAX_PAGES = 10
    NAME = "PlanetScale".freeze

    def initialize(authorization)
      @authorization = authorization
    end

    # A database's deploy requests, newest first (List deploy requests). into_branch and state are PlanetScale's own
    # filters, state one of open, closed or deployed.
    def deploy_requests(organization, database, into_branch: nil, state: nil, per_page: 25)
      body = get(database_path(organization, database, "deploy-requests"), { "into_branch" => into_branch.presence, "state" => state.presence, "per_page" => per_page })
      Array(body["data"])
    end

    def deploy_request(organization, database, number) = get(deploy_request_path(organization, database, number))

    # The deployment of a deploy request, with its operations, lint errors and revert (Get a deployment).
    def deployment(organization, database, number) = get(deploy_request_path(organization, database, number, "deployment"))

    # Each schema change a deploy request makes, with its state, progress and the error PlanetScale gave (List deploy
    # operations), every page up to the bound.
    def deploy_operations(organization, database, number)
      paged(deploy_request_path(organization, database, number, "operations"))
    end

    # The changes to a deploy request's run, each a POST PlanetScale documents, answering the deploy request.
    DEPLOY_ACTIONS = %w[revert cancel skip-revert force-cutover apply-deploy complete-deploy].freeze

    def act_on_deploy_request(organization, database, number, action)
      raise ArgumentError, "#{action} is not a deploy request change PlanetScale documents" unless DEPLOY_ACTIONS.include?(action)

      write(Net::HTTP::Post, deploy_request_path(organization, database, number, action))
    end

    def database(organization, database) = get(database_path(organization, database))

    def branch(organization, database, branch) = get(branch_path(organization, database, branch))

    # A Postgres branch's cluster changes, its size, replicas, storage and parameters (Get branch change requests).
    def branch_changes(organization, database, branch) = paged(branch_path(organization, database, branch, "changes"))

    # A Vitess branch's VTGate resizes (Get branch resize requests) and its configuration changes (List branch config change
    # requests).
    def branch_resizes(organization, database, branch) = paged(branch_path(organization, database, branch, "resizes"))

    def branch_config_changes(organization, database, branch) = paged(branch_path(organization, database, branch, "config-changes"))

    # A Vitess keyspace's resizes (Get keyspace resize requests).
    def keyspace_resizes(organization, database, branch, keyspace)
      paged(branch_path(organization, database, branch, "keyspaces", keyspace, "resizes"))
    end

    # Asks for a Postgres branch's cluster size or replica count (Upsert a change request), a Vitess keyspace's cluster size
    # or extra replicas (Upsert a keyspace resize request), or a Vitess branch's VTGates (Upsert a resize request).
    def change_branch(organization, database, branch, body) = write(Net::HTTP::Patch, branch_path(organization, database, branch, "changes"), body)

    def resize_keyspace(organization, database, branch, keyspace, body)
      write(Net::HTTP::Put, branch_path(organization, database, branch, "keyspaces", keyspace, "resizes"), body)
    end

    def resize_vtgates(organization, database, branch, body) = write(Net::HTTP::Put, branch_path(organization, database, branch, "resizes"), body)

    def promote(organization, database, branch) = write(Net::HTTP::Post, branch_path(organization, database, branch, "promote"))

    def demote(organization, database, branch) = write(Net::HTTP::Post, branch_path(organization, database, branch, "demote"))

    # Every database of an organization the token reaches (List databases), up to the bound, as a Pages::Read.
    def databases(organization)
      Pages.read(max_pages: MAX_PAGES) do |page|
        page ||= 1
        body = get("/organizations/#{Http.segment(organization)}/databases", { "page" => page, "per_page" => PER_PAGE })
        [ Array(body["data"]), (page + 1 if body["next_page"].present?) ]
      end
    end

    # A database's webhooks (List webhooks), each with its address, events and secret.
    def webhooks(organization, database) = paged(database_path(organization, database, "webhooks"))

    # A webhook PlanetScale signs with a secret it makes, which its answer carries (Create a webhook).
    def create_webhook(organization, database, url:, events:)
      write(Net::HTTP::Post, database_path(organization, database, "webhooks"), { "url" => url, "events" => events, "enabled" => true })
    end

    def update_webhook(organization, database, id, events:)
      write(Net::HTTP::Patch, database_path(organization, database, "webhooks", id), { "events" => events, "enabled" => true })
    end

    def delete_webhook(organization, database, id)
      uri = URI.parse("#{API_ROOT}#{database_path(organization, database, 'webhooks', id)}")
      send_request(uri, Net::HTTP::Delete.new(uri))
    end

    private

    def database_path(organization, database, *rest)
      [ "/organizations", organization, "databases", database, *rest ].map.with_index { |part, index| index.zero? ? part : Http.segment(part.to_s) }.join("/")
    end

    def branch_path(organization, database, branch, *rest) = database_path(organization, database, "branches", branch, *rest)

    def deploy_request_path(organization, database, number, *rest) = database_path(organization, database, "deploy-requests", number, *rest)

    # Every page of a list, up to the bound.
    def paged(path)
      Pages.read(max_pages: MAX_PAGES) do |page|
        page ||= 1
        body = get(path, { "page" => page, "per_page" => PER_PAGE })
        [ Array(body["data"]), (page + 1 if body["next_page"].present?) ]
      end.items
    end

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def write(verb, path, body = nil)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = verb.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def send_request(uri, request)
      request["Authorization"] = @authorization
      request["Accept"] = "application/json"
      Http.json(uri, request, error_class: Error, provider_name: NAME, refine: ->(code, _reason) { REFINED[code] })
    end
  end
end
